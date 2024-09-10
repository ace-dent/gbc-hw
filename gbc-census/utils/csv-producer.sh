#!/bin/bash

# WARNING: Not safe for public use!
#   Created for the author's benefit
#   Assumes:
#   - Correctly formatted main `.csv` file is fed in


# Minimal checks for input file
if [[ -z "$1" ]]; then
  echo 'Missing filename. Provide a CSV file to process.'
  exit
fi
file_check="${1%.*}"'.csv'
if [[ ! -f "${file_check}" ]]; then
  echo 'File not found. Check `.csv` file extension.'
  exit
fi


# Make sure the header fields have no trailing spaces
#  and change the text `Timestamp` to `Date`.
sed -i '' 's/ ,/,/g; s/Timestamp/Date/g' "$1"
# TODO: Generate the separate CSV files, each with a header -
#   header="$(head -n 1 "$1" | sed 's/ ,/,/g; s/Timestamp/Date/g')"


# Enclose PCB numbers `,0n,` in double quotes `,"0n",` (n=2-6),
#   to ensure they are treated as text fields when importing the CSV.
# We don't enclose implicit text fields, to save some bytes.
for i in {2..6}; do
    sed -i '' "s/,0$i,/,\"0$i\",/g" "$1"
done


# TODO:
# For the special edition `X` series, we need to move the `POB` serials to the
#   start of the list. This prioritizes release order, over alphabetic sorting.


# Add the version and copyright notice in the footer
copyright='Copyright (C) Andrew C.E. Dent 2022'
# Get the current date formatted as DD-Mmm-YYYY and also the year YYYY
date_full=$(date +'%d-%b-%Y')
date_year=$(date +'%Y')
# We use the number of entries (rows - 1x header) as a revision number `R0###`,
#   for document version control.
row_count=$(($(wc -l < "$1") - 1))
# Append footer to file(s)
for file in "$1"; do
    {
        printf ',,,,,,\n'
        printf '%s, R%04u,,,,, %s-%u.\n' "${date_full}" "${row_count}" "${copyright}" "${date_year}"
        printf '           ,      ,,,,, This work is licensed under CC BY-NC-SA. See:\n'
        printf '           ,      ,,,,, https://creativecommons.org/licenses/by-nc-sa/4.0/\n'
    } >> "${file}"
done
