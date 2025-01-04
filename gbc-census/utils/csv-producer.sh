#!/bin/bash

# WARNING: Not safe for public use!
#   Created for the author's benefit.
#   Assumes:
#   - Correctly formatted main `.csv` file is fed in, to be split by serial


# Minimal checks for input file
if [[ -z "$1" ]]; then
  echo 'Missing filename. Provide a CSV file to process.'
  exit
fi
file_check="${1%.*}"'.csv'
if [[ ! -f "${file_check}" ]]; then
  echo 'File not found. Check CSV file extension.'
  exit
fi
file_size=$(stat -f%z "$1")
if (( file_size < 1024 || file_size > 2097152 )); then
  echo "File size is outside the allowed range (1 KiB - 2 MiB)."
  exit
fi

# Files to be created
dir=$(dirname "$1")
file_C="${dir}"'/gbc-census-C.csv'
file_CG="${dir}"'/gbc-census-CG.csv'
file_CH="${dir}"'/gbc-census-CH.csv'
file_X="${dir}"'/gbc-census-X.csv'
# Temporary file buffers
buffer_C=''
buffer_CG=''
buffer_CH=''
buffer_POB=''
buffer_X=''


# Make sure the header fields have no trailing spaces
#  and change the text `Timestamp` to `Date`.
header="$(head -n 1 "$1" | sed 's/ ,/,/g; s/Timestamp/Date/g')"
# Create the files with header row
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  echo "$header" > "$file"
done


# Enclose PCB numbers `,0n,` in double quotes `,"0n",` (n=2-6),
#   to ensure they are treated as text fields when importing the CSV.
# We don't enclose implicit text fields, to save some bytes.
for i in {2..6}; do
  sed -i '' "s/,0$i,/,\"0$i\",/g" "$1"
done


# Process each row, skipping the header
while IFS=, read -r col1 col2 col_rest; do
  if [[ "${col2}" =~ ^C[0-9] ]]; then
    buffer_C+="${col1},${col2},${col_rest}"$'\n'
  elif [[ "${col2}" =~ ^CG[0-9] ]]; then
    buffer_CG+="${col1},${col2},${col_rest}"$'\n'
  elif [[ "${col2}" =~ ^CH[0-9] ]]; then
    buffer_CH+="${col1},${col2},${col_rest}"$'\n'
  elif [[ "${col2}" =~ ^POB\ [0-9] ]]; then
    buffer_POB+="${col1},${col2},${col_rest}"$'\n'
  else
    buffer_X+="${col1},${col2},${col_rest}"$'\n'
  fi
done < <(tail -n +2 "$1")
# Write buffers to files
echo -n "${buffer_C}" >> "${file_C}"
echo -n "${buffer_CG}" >> "${file_CG}"
echo -n "${buffer_CH}" >> "${file_CH}"
# For the special edition `X` series, we move the `POB` serials to the start.
#   This prioritizes release order, over alphabetic sorting.
echo -n "${buffer_POB}" >> "${file_X}"
echo -n "${buffer_X}" >> "${file_X}"


# Add the version and copyright notice in the footer
readonly copyright='Copyright (C) Andrew C.E. Dent 2022'
# Get the current date formatted as DD-Mmm-YYYY and also the year YYYY
date_full=$(date +'%d-%b-%Y')
date_year=$(date +'%Y')
# We use the number of entries (rows - 1x header) as a revision number `R0###`,
#   for document version control.
row_count=$(($(wc -l < "$1") - 1))
# Append footer to file(s)
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  {
    printf ',,,,,,\n'
    printf '%s, R%04u,,,,, %s-%u.\n' "${date_full}" "${row_count}" "${copyright}" "${date_year}"
    printf '           ,      ,,,,, This work is licensed under CC BY-NC-SA. See:\n'
    printf '           ,      ,,,,, https://creativecommons.org/licenses/by-nc-sa/4.0/\n'
  } >> "${file}"
done

# TODO: Add some sanity checks for the output files.
#   E.g. make sure rows sum to the total.
