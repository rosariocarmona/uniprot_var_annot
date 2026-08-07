#!/bin/bash

# Terminar el script si ocurre algún error
set -e

# 1. Validar el argumento de entrada
if [ $# -lt 1 ]; then
    echo "Uso: $0 <fichero_de_entrada.tsv> [<fichero_de_salida.tsv>]"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: El fichero de entrada '$INPUT_FILE' no existe."
    exit 1
fi

# 2. Descargar el archivo humsavar.txt en la carpeta databases/
URL="https://ftp.uniprot.org/pub/databases/uniprot/knowledgebase/variants/humsavar.txt"
DB_DIR="databases"
mkdir -p "$DB_DIR"

RAW_HUMSAVAR="$DB_DIR/humsavar_raw.txt"

echo "Descargando humsavar.txt desde UniProt..."
curl -s -L "$URL" -o "$RAW_HUMSAVAR" || wget -q -O "$RAW_HUMSAVAR" "$URL"

# 3. Extraer la versión de Release y renombrar el archivo
RELEASE_VER=$(grep -i "^Release:" "$RAW_HUMSAVAR" | head -n 1 | awk '{print $2}')

if [ -z "$RELEASE_VER" ]; then
    RELEASE_VER="unknown"
fi

DB_FILE="$DB_DIR/humsavar_${RELEASE_VER}.txt"
mv "$RAW_HUMSAVAR" "$DB_FILE"
echo "Archivo de base de datos guardado como: $DB_FILE"

# 4. Determinar nombre del fichero de salida
if [ $# -ge 2 ]; then
    OUTPUT_FILE="$2"
else
    BASENAME=$(basename "$INPUT_FILE")
    DIRNAME=$(dirname "$INPUT_FILE")
    if [ "$DIRNAME" = "." ]; then
        OUTPUT_FILE="humansavarAnnot_${BASENAME}"
    else
        OUTPUT_FILE="${DIRNAME}/humansavarAnnot_${BASENAME}"
    fi
fi

echo "Procesando la anotación en $OUTPUT_FILE ..."

# 5. Ejecutar script en Python para parsear la BD y hacer el cruce de datos
python3 - "$DB_FILE" "$INPUT_FILE" "$OUTPUT_FILE" << 'EOF'
import sys
import re

db_file = sys.argv[1]
input_file = sys.argv[2]
output_file = sys.argv[3]

# 1. Cargar y parsear humsavar
humsavar_dict = {}

with open(db_file, 'r', encoding='utf-8', errors='ignore') as f:
    start_reading = False
    for line in f:
        # Detectar la línea separadora que indica el inicio de los datos
        if not start_reading:
            if line.startswith("______") or line.startswith("------"):
                start_reading = True
            continue
        
        # Omitir líneas vacías o de pie de página
        if not line.strip() or line.startswith("------") or line.startswith("______"):
            continue
            
        # Parsear las columnas de humsavar por campos delimitados por espacios
        parts = line.strip().split()
        if len(parts) >= 6:
            main_gene = parts[0]
            swissprot_ac = parts[1]
            ftid = parts[2]
            aa_change = parts[3]
            variant_cat = parts[4]
            dbsnp = parts[5]
            disease_name = " ".join(parts[6:]) if len(parts) > 6 else "-"
            
            # Llave compuesta: (Main_gene_name, Swiss-Prot_AC, AA_change)
            key = (main_gene, swissprot_ac, aa_change)
            value = f"{variant_cat} ({disease_name})"
            humsavar_dict[key] = value

# 2. Leer archivo de entrada y anotar la nueva columna
with open(input_file, 'r', encoding='utf-8') as f_in, open(output_file, 'w', encoding='utf-8') as f_out:
    header_line = f_in.readline()
    if not header_line:
        sys.exit(0)
        
    headers = header_line.rstrip('\r\n').split('\t')
    
    # Identificar índices de las columnas requeridas
    try:
        idx_gene = headers.index('gene')
        idx_uniprot = headers.index('uniprot_id')
        idx_aa = headers.index('aa_acid_change')
    except ValueError as e:
        print(f"Error: No se encontró alguna de las columnas requeridas ('gene', 'uniprot_id', 'aa_acid_change') en el fichero de entrada: {e}")
        sys.exit(1)
        
    # Escribir la nueva cabecera
    new_headers = headers + ['UniProt_CuratedClassif']
    f_out.write('\t'.join(new_headers) + '\n')
    
    # Procesar filas
    for line in f_in:
        if not line.strip():
            continue
        fields = line.rstrip('\r\n').split('\t')
        
        # Obtener valores para la comparación
        gene_val = fields[idx_gene] if idx_gene < len(fields) else ""
        uniprot_val = fields[idx_uniprot] if idx_uniprot < len(fields) else ""
        aa_val = fields[idx_aa] if idx_aa < len(fields) else ""
        
        # Buscar coincidencia
        key = (gene_val, uniprot_val, aa_val)
        annotation = humsavar_dict.get(key, "-")
        
        new_fields = fields + [annotation]
        f_out.write('\t'.join(new_fields) + '\n')

print("¡Proceso completado con éxito!")
EOF