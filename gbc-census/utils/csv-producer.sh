#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
# SPDX-FileCopyrightText: © 2024 Andrew C.E. Dent <hi@aced.cafe>
#
# -----------------------------------------------------------------------------
# Usage:
#   - Provide main CSV file, to be split by serial number into separate files.
#   - Outputs 4 CSV files: gbc-census-C /-CG /-CH /-X.
#
# Assumptions:
#   - Filenames and directory structures follow the project standard.
#   - Correctly formatted main `.csv` file is fed in, sorted by serial number.
#
# WARNING:
#   May not be safe for public use; created for the author's benefit.
#   Provided "as is", without warranty of any kind; see the
#   accompanying LICENSE file for full terms. Use at your own risk!
# -----------------------------------------------------------------------------


#  Pretty messages, colored if NO_COLOR is unset and stdout is a valid terminal
ERR='✖ Error:' WARN='▲ Warning:'
[[ -z "${NO_COLOR-}" && -t 1 && "${TERM-}" != dumb ]] \
  && ERR=$'\e[31m'$ERR$'\e[0m' WARN=$'\e[33m'$WARN$'\e[0m'

# Minimal checks for input file
if [[ -z "$1" ]]; then
  echo "${ERR} Missing filename. Provide a CSV file to process."
  exit
fi
if [[ ! -f "${1%.*}.csv" || ! -r "$1" ]]; then
  echo "${ERR} File not accessible. CSV file required."
  exit
fi
file_size=$(stat -f%z "$1")
if (( file_size < 1024 || file_size > 2097152 )); then
  echo "${ERR} File size is outside the allowed range (1 KiB - 2 MiB)."
  exit
fi

echo ''
echo "Processing CSV file: '$1' ..."


# We use the number of entries (rows - 1x header) as a revision number `R0###`,
#   for document version control and checking the input
row_count=$(($(wc -l < "$1") - 1))
if [[ "${row_count}" -le 100 ]]; then
  echo "${ERR} Input file is too short. Expected over 100 rows."
  exit
fi

# Check 'signature': first and last rows of input data match known values
#   Fill these in to match the dataset exactly (including commas)
readonly row_a='05-Nov-2024,C10101593,'
readonly row_z='31-Oct-2024,POB 24237,'
first_data_row=$(sed -n '2p' "$1") # Read second line, skipping the header
# Determine last data row, accounting for potential blank final line
last_line=$(tail -n1 "$1")
if [[ -z "${last_line}" ]]; then
  # Skip the blank footer line and read penultimate row (n-1)
  last_data_row=$(sed -n "${row_count}p" "$1")
else
  last_data_row="${last_line}"
fi
if [[ "${first_data_row}" != ${row_a}* ]]; then
  echo "${ERR} First row of data doesn't match expected value: '${row_a}'."
  exit
fi
if [[ "${last_data_row}" != ${row_z}* ]]; then
  echo "${ERR} Last row of data doesn't match expected value: '${row_z}'."
  exit
fi


# Files to be created
dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
readonly file_C="${dir}"'/gbc-census-C.csv'
readonly file_CG="${dir}"'/gbc-census-CG.csv'
readonly file_CH="${dir}"'/gbc-census-CH.csv'
readonly file_X="${dir}"'/gbc-census-X.csv'
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
  echo "${header}" > "${file}"
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
# Append footer to file(s)
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  {
    printf ',,,,,,\n'
    printf '%s, R%05u,,,,, %s-%u.\n' "${date_full}" "${row_count}" "${copyright}" "${date_year}"
    printf '           ,      ,,,,, This work is licensed under CC BY-NC-SA. See:\n'
    printf '           ,      ,,,,, https://creativecommons.org/licenses/by-nc-sa/4.0/\n'
    printf '           ,      ,,,,, Provided “as is”, without warranty of any kind.'
  } >> "${file}"
done


# Check output: Verify split-row counts match original total
total_out_rows=0
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  if [[ ! -r "${file}" ]]; then
    echo "${ERR} Output file is missing or unreadable: $file"
    exit
  fi
  count=$(( $(wc -l < "${file}") - 1 - 5 )) # subtract header and footer rows
  total_out_rows=$(( total_out_rows + count ))
done
if [[ "${total_out_rows}" -ne "${row_count}" ]]; then
  echo "${ERR} Total output rows ($total_out_rows) does not match input ($row_count)!"
  exit
fi


echo '...Finished :)'
echo ''
exit
