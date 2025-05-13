#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status
set -u # Exit if a var is undefined
set -o pipefail # exit status of a pipeline is the exit status of the last command to fail


# Define the printer name and test PDF file
PRINTER_NAME="Your_AirPrint_Printer_Name" # TODO
TEST_PDF="/home/will/smarthomeserver/printer-maintenance/testprint.pdf"

# Check if the test PDF file exists
if [[ ! -f "$TEST_PDF" ]]; then
    echo "Error: Test PDF file not found at $TEST_PDF"
    exit 1
fi

# Get the last completed print job for the printer
LAST_PRINT=$(lpstat -W completed | grep "$PRINTER_NAME" | tail -n 1)

if [[ -n "$LAST_PRINT" ]]; then
    echo "The last print job for $PRINTER_NAME was:"
    echo "$LAST_PRINT"
else
    echo "No completed print jobs found for $PRINTER_NAME."
fi

# Send the test PDF to the printer using lp command
lp -d "$PRINTER_NAME" "$TEST_PDF"

# Check if the print command was successful
if [[ $? -eq 0 ]]; then
    echo "Test print sent successfully to $PRINTER_NAME."
else
    echo "Failed to send test print to $PRINTER_NAME."
    exit 1
fi


# TODO: Add to crontab
#
# 0 11 * * 1 [ $(($(date +%U) % 2)) -eq 0 ] && /home/will/smarthomeserver/printer-maintenance/print_maintenance_page.sh
#
# 0 11 * * 1: Runs at 11:00 AM every Monday.
# [ $(($(date +%U) % 2)) -eq 0 ]: Ensures the script runs only on even weeks (%U gives the week number of the year).
# print_maintenance_page.sh: Path to your script.
