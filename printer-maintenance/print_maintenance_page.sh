#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status
set -u # Exit if a var is undefined

echo Printing maintenance page...

# Define the printer name and test PDF file
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Script directory: $SCRIPT_DIR"
cd "$SCRIPT_DIR" || exit 1
echo pwd "$PWD"

PRINTER_NAME="HP_Smart_Tank_7300_series_88381A"
TEST_PDF="./testprint.pdf"

# Check if the test PDF file exists
if [[ ! -f "$TEST_PDF" ]]; then
    echo "Error: Test PDF file not found at $TEST_PDF"
    exit 1
fi
# Get the last completed print job for the printer
LAST_PRINT=$(lpstat -W completed | grep "$PRINTER_NAME" | tail -n 1)

if [[ -n "$LAST_PRINT" ]]; then
    echo "The last print job for $PRINTER_NAME was:"
    echo "$LAST_PRINT\n"
else
    echo "No completed print jobs found for $PRINTER_NAME."
fi

# Create a watermark PNG with the current date
WATERMARK_PNG="./watermark.png"
WATERMARK_PDF="./watermark.pdf"
WATERMARKED_PDF="./testprint_watermarked.pdf"
DATE_STR=$(date +"%Y-%m-%d %H:%M:%S")

echo "Creating watermark with date: $DATE_STR"
convert -size 595x842 xc:none -gravity south -pointsize 48 -fill grey -annotate +0+40 "$DATE_STR" "$WATERMARK_PNG"
img2pdf "$WATERMARK_PNG" -o "$WATERMARK_PDF" --pagesize A4
pdftk "$TEST_PDF" stamp "$WATERMARK_PDF" output "$WATERMARKED_PDF"

rm "$WATERMARK_PNG" "$WATERMARK_PDF" # Clean up the watermark files

# --- Add a page with neofetch output centered ---

NEOFETCH_HTML="./neofetch.html"
NEOFETCH_PNG="./neofetch.png"
NEOFETCH_PDF="./neofetch.pdf"

neofetch | aha --title "Neofetch" > "$NEOFETCH_HTML"
wkhtmltoimage --width 595 --height 842 --quality 100 "$NEOFETCH_HTML" "$NEOFETCH_PNG"
img2pdf "$NEOFETCH_PNG" -o "$NEOFETCH_PDF" --pagesize A4

rm "$NEOFETCH_HTML" "$NEOFETCH_PNG" # Clean up the neofetch files

# Combine the watermarked PDF and the neofetch PDF
FINAL_PDF="./testprint_final.pdf"
pdftk "$WATERMARKED_PDF" "$NEOFETCH_PDF" cat output "$FINAL_PDF"

rm $NEOFETCH_PDF "$WATERMARKED_PDF" # Clean up the intermediate files

# Send the test PDF to the printer using lp command
lp -d "$PRINTER_NAME" "$FINAL_PDF" -o fit-to-page -o media=A4 -o orientation-requested=5 -o sides=two-sided-long-edge

# Check if the print command was successful
if [[ $? -eq 0 ]]; then
    echo "Maintenance page sent successfully to $PRINTER_NAME."
else
    echo "Failed to send maintenance page to $PRINTER_NAME."
    exit 1
fi


# TODO: Add to crontab
#
# 0 11 * * 1 [ $(($(date +%U) % 2)) -eq 0 ] && /home/will/smarthomeserver/printer-maintenance/print_maintenance_page.sh
#
# 0 11 * * 1: Runs at 11:00 AM every Monday.
# [ $(($(date +%U) % 2)) -eq 0 ]: Ensures the script runs only on even weeks (%U gives the week number of the year).
# print_maintenance_page.sh: Path to your script.
