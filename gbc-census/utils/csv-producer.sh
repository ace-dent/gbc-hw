#!/usr/bin/env bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
# SPDX-FileCopyrightText: © 2024 Andrew C.E. Dent <hi@aced.cafe>
#
# -----------------------------------------------------------------------------
# Usage:
#   - Provide main CSV file, to be split by serial number into separate files.
#   - Outputs 4 CSV files: gbc-census-C /-CG /-CH /-X.
#
# Requirements:
#   - Bash v3.0+
#   - Optional: yq (updates citation.cff yaml file)
#
# Assumptions:
#   - Filenames and directory structures follow the project standard.
#   - Correctly formatted main `.csv` file is fed in, sorted by serial number.
#
# WARNING:
#     May not be safe for public use; created for the author's benefit.
#     Provided "as is", without warranty of any kind. See the
#     accompanying LICENSE file for full terms. Use at your own risk!
# -----------------------------------------------------------------------------

# Strict mode: immediately exit on error, an unset variable or pipe failure
set -euo pipefail

# Message decorations - colored for terminals if NO_COLOR is unset
ERR='✖ Error:' WARN='▲ Warning:' DONE='⚑'
[[ -z "${NO_COLOR-}" && -t 2 && "${TERM-}" != dumb ]] \
  && ERR=$'\e[1;31m'$ERR$'\e[m' WARN=$'\e[1;33m'$WARN$'\e[m'

# Set POSIX locale for consistent byte-wise sorting and pattern matching
export LC_COLLATE=C
# Check the system character map supports Unicode glyphs
if [[ "$(locale charmap)" != *UTF-8* ]]; then
  echo "${WARN} System locale may not support extended UTF-8 characters." >&2
fi
# Minimal checks for input file
if [[ -z "${1:-}" ]]; then
  echo "${ERR} Missing filename. Provide a CSV file to process." >&2
  exit 1
fi
if [[ ! -r "$1" || ! "$1" =~ \.(csv|CSV)$ ]]; then
  echo "${ERR} A readable CSV file is required." >&2
  exit 1
fi
declare -i file_size=$(stat -f%z "$1" 2>/dev/null || wc -c <"$1")
if (( file_size < 1024 || file_size > 2097152 )); then
  echo "${ERR} File size is outside the allowed range (1 KiB - 2 MiB)." >&2
  exit 1
fi

echo ''
echo "Processing: '$1' ..."


# We use the number of entries (rows - 1x header) as a revision number `R01234`,
#   for document version control and checking the input
declare -i row_count=$(( $(wc -l < "$1") - 1 ))
if (( row_count < 100 || row_count > 20000 )); then
  echo "${ERR} Row count is outside the allowed range (100 - 20k)." >&2
  exit 1
fi

# Check 'signature': first and last rows of input data match known values
readonly row_a='2025-06-17,C10003149,CGB-JPN,'
readonly row_z='2024-10-31,POB 24237,CGB-POB-JPN,'
first_data_row=$(sed -n '2p' "$1") # Read second line, skipping the header
# Determine last data row, accounting for potential blank final line
last_data_row=$(tail -n1 "$1")
if [[ -z "${last_data_row//[[:space:]]/}" ]]; then
  # Skip the blank footer line and read penultimate row (n-1)
  last_data_row=$(sed -n "${row_count}p" "$1")
fi
if [[ "${first_data_row}" != ${row_a}* ]]; then
  echo "${ERR} First row of data doesn't begin with: '${row_a}'." >&2
  exit 1
fi
if [[ "${last_data_row}" != ${row_z}* ]]; then
  echo "${ERR} Last row of data doesn't begin with: '${row_z}'." >&2
  exit 1
fi


# Files to be created
root_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly file_C="${root_dir}/gbc-census-C.csv"
readonly file_CG="${root_dir}/gbc-census-CG.csv"
readonly file_CH="${root_dir}/gbc-census-CH.csv"
readonly file_X="${root_dir}/gbc-census-X.csv"
readonly files=("${file_C}" "${file_CG}" "${file_CH}" "${file_X}")
# Temporary array buffers for each serial group, to reduce disk operations
declare -a rows_C rows_CG rows_CH rows_POB rows_X

# Create each file with header rows
for file in "${files[@]}"; do
  printf 'Serial number,Production,PCB #,Panel (A-B),Shell,Source,Date\n' > "${file}" \
    || { echo "${ERR} Failed writing to file: '${file}'." >&2; exit 1; }
done


# Place each CSV row into the correct serial group, skipping the header
while IFS=, read -r date serial production pcb other_columns; do
  # Enclose PCB numbers `,0n,` in double quotes `,"0n",` (n=2-6),
  #   to ensure they are treated as text fields when importing the CSV
  if [[ "${pcb}" =~ ^0[2-6]$ ]]; then
    pcb="\"${pcb}\""
  fi
  # Move date column to the end of each row
  row="${serial},${production},${pcb},${other_columns},${date}"
  case "${serial}" in
    C[0-9]*)
      rows_C+=("${row}")
      ;;
    CG[0-9]*)
      rows_CG+=("${row}")
      ;;
    CH[0-9]*)
      rows_CH+=("${row}")
      ;;
    'POB '[0-9]*)
      rows_POB+=("${row}")
      ;;
    'CWP '[0-9]*)
      rows_X+=("${row}")
      ;;
    PD[0-9]*)
      rows_X+=("${row}")
      ;;
    *)
      # Ignore BR distributor Gradiente Entertainment: 123456789A1B
      # Ignore: AU12345678
      echo "${WARN} skipped '${row}'" >&2
      ;;
  esac
done < <(tail -n +2 "$1")
# Write each buffers to its corresponding file
printf '%s\n' "${rows_C[@]}" >> "${file_C}"
printf '%s\n' "${rows_CG[@]}" >> "${file_CG}"
printf '%s\n' "${rows_CH[@]}" >> "${file_CH}"
# For the special edition `X` series, we move the `POB` serials to the start
#   This prioritizes release order, over alphabetic sorting
{
  printf '%s\n' "${rows_POB[@]}"
  printf '%s\n' "${rows_X[@]}"
} >> "${file_X}"


# Add the version and copyright notice in the footer
readonly copyright='Copyright (C) Andrew C.E. Dent 2022'
# Get the current date formatted as YYYY-MM-DD (ISO 8601) and the year YYYY
date_full=$(date '+%F')
date_year=$(date '+%Y')
# Append footer to file(s)
for file in "${files[@]}"; do
  {
    printf ',,,,,,\n'
    printf ',,,,,, %s-%u. \n' "${copyright}" "${date_year}"
    printf ',,,,,, This work is licensed under CC BY-NC-SA. See: \n'
    printf ',,,,,, https://creativecommons.org/licenses/by-nc-sa/4.0/ \n'
    printf ',,,,,, Provided “as is”- without warranty of any kind. \n'
    printf ',,,,,, (Release: %s / R%05u) \n' "${date_full}" "${row_count}"
  } >> "${file}"
done


# Check output: Verify separate row counts match original total
declare -i total_out_rows count
for file in "${files[@]}"; do
  if [[ ! -r "${file}" ]]; then
    echo "${ERR} Output file is missing or unreadable: ${file}" >&2
    exit 1
  fi
  count=$(( $(wc -l < "${file}") -1 -6 )) # Subtract header and footer rows
  total_out_rows=$(( total_out_rows + count ))
done
if (( total_out_rows != row_count )); then
  echo "${ERR} Total output rows (${total_out_rows}) does not match input (${row_count})!" >&2
  exit 1
else
  echo "${row_count} rows split into corresponding CSV files."
fi


# Optionally update CITATION.cff yaml file with the release details
if command -v 'yq' &> /dev/null; then
  env VERSION="R0${row_count}" DATE="${date_full}" \
    yq -i '
      .version = strenv(VERSION) |
      .date-released = strenv(DATE)
    ' "${root_dir}/CITATION.cff"
fi


echo " ...Finished! ${DONE}"
echo ''
exit 0
