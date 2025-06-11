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
#
# Assumptions:
#   - Filenames and directory structures follow the project standard.
#   - Correctly formatted main `.csv` file is fed in, sorted by serial number.
#
# WARNING:
#     May not be safe for public use; created for the author's benefit.
#     Provided "as is", without warranty of any kind; see the
#     accompanying LICENSE file for full terms. Use at your own risk!
# -----------------------------------------------------------------------------

# Strict mode: immediately exit on error, an unset variable or pipe failure
set -euo pipefail

# Set POSIX locale for consistent byte-wise sorting and pattern matching
export LC_COLLATE=C

# Message decorations - colored for terminals with NO_COLOR unset
ERR='✖ Error:' WARN='▲ Warning:' DONE='⚑'
[[ -z "${NO_COLOR-}" && -t 1 && "${TERM-}" != dumb ]] \
  && ERR=$'\e[1;31m'$ERR$'\e[m' WARN=$'\e[1;33m'$WARN$'\e[m'

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
file_size=$(stat -f%z "$1" 2>/dev/null || wc -c <"$1")
if (( file_size < 1024 || file_size > 2097152 )); then
  echo "${ERR} File size is outside the allowed range (1 KiB - 2 MiB)." >&2
  exit 1
fi

echo ''
echo "Processing: '$1' ..."


# We use the number of entries (rows - 1x header) as a revision number `R01234`,
#   for document version control and checking the input
row_count=$(( $(wc -l < "$1") - 1 ))
if [[ "${row_count}" -lt 100  || "${row_count}" -gt 20000 ]]; then
  echo "${ERR} Row count is outside the allowed range (100 - 20k)." >&2
  exit 1
fi

# Check 'signature': first and last rows of input data match known values
#   Fill these in to match the dataset exactly (including commas)
readonly row_a='2024-11-05,C10101593,'
readonly row_z='2024-10-31,POB 24237,'
first_data_row=$(sed -n '2p' "$1") # Read second line, skipping the header
# Determine last data row, accounting for potential blank final line
last_line=$(tail -n1 "$1")
if [[ -z "${last_line//[[:space:]]/}" ]]; then
  # Skip the blank footer line and read penultimate row (n-1)
  last_data_row=$(sed -n "${row_count}p" "$1")
else
  last_data_row="${last_line}"
fi
if [[ "${first_data_row}" != ${row_a}* ]]; then
  echo "${ERR} First row of data doesn't match expected value: '${row_a}'." >&2
  exit 1
fi
if [[ "${last_data_row}" != ${row_z}* ]]; then
  echo "${ERR} Last row of data doesn't match expected value: '${row_z}'." >&2
  exit 1
fi


# Files to be created
dir="$(dirname "${BASH_SOURCE[0]}")/.."
readonly file_C="${dir}"'/gbc-census-C.csv'
readonly file_CG="${dir}"'/gbc-census-CG.csv'
readonly file_CH="${dir}"'/gbc-census-CH.csv'
readonly file_X="${dir}"'/gbc-census-X.csv'
# Temporary array buffers (for each serial group)
rows_C=()
rows_CG=()
rows_CH=()
rows_POB=()
rows_X=() # All other serial rows


# Make sure the header fields have no trailing spaces
#  and change the text `Timestamp` to `Date`
header="$(head -n 1 "$1" | sed 's/ ,/,/g; s/Timestamp/Date/g')"
# Create the files with header row
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  printf '%s\n' "$header" > "${file}" \
    || { echo "${ERR} Failed writing to file: '${file}'." >&2; exit 1; }
done


# Enclose PCB numbers `,0n,` in double quotes `,"0n",` (n=2-6),
#   to ensure they are treated as text fields when importing the CSV
# We don't enclose implicit text fields, to save some bytes
for i in {2..6}; do
  sed -i '' "s/,0$i,/,\"0$i\",/g" "$1"
done


# Place each CSV row into the correct serial group, skipping the header
while IFS=, read -r date serial other_columns; do
  row="${date},${serial},${other_columns}"
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
    *)
      rows_X+=("${row}")
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
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  {
    printf ',,,,,,\n'
    printf '%s, R%05u,,,,, %s-%u.\n' "${date_full}" "${row_count}" "${copyright}" "${date_year}"
    printf '          ,       ,,,,, This work is licensed under CC BY-NC-SA. See:\n'
    printf '          ,       ,,,,, https://creativecommons.org/licenses/by-nc-sa/4.0/\n'
    printf '          ,       ,,,,, Provided “as is”- without warranty of any kind.\n'
  } >> "${file}"
done


# Check output: Verify split-row counts match original total
total_out_rows=0
for file in "${file_C}" "${file_CG}" "${file_CH}" "${file_X}"; do
  if [[ ! -r "${file}" ]]; then
    echo "${ERR} Output file is missing or unreadable: $file" >&2
    exit 1
  fi
  count=$(( $(wc -l < "${file}") -1 -5 )) # Subtract header and footer rows
  total_out_rows=$(( total_out_rows + count ))
done
if [[ "${total_out_rows}" -ne "${row_count}" ]]; then
  echo "${ERR} Total output rows (${total_out_rows}) does not match input (${row_count})!" >&2
  exit 1
else
  echo "${row_count} rows split into corresponding CSV files."
fi


echo " ...Finished! ${DONE}"
echo ''
exit 0
