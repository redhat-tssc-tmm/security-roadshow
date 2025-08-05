#!/bin/bash

# Check if both parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <quayuser> <quaypassword>"
    exit 1
fi

# Assign parameters to variables
QUAYUSER="$1"
QUAYPASSWORD="$2"


# ASCII art warning sign
echo "   ╔═════════════════════╗"
echo "   ║                     ║"
echo "   ║   ⚠️  CAUTION  ⚠️     ║"
echo "   ║                     ║"
echo "   ║  CONSTRUCTION SITE  ║"
echo "   ║                     ║"
echo "   ║                     ║"
echo "   ║   MIND YOUR STEP!   ║"
echo "   ║                     ║"
echo "   ╚═════════════════════╝"
echo "            ║   ║"
echo "            ║   ║"
echo "        ════╩═══╩════"
echo ""

# Print the parameters
echo "Parameters received:"
echo "Quay User: $QUAYUSER"
echo "Quay Password: $QUAYPASSWORD"
echo ""
