#!/usr/bin/env python3
"""
generate_phase1_doc.py
Converts PHASE1_TECHNICAL_DOCUMENT.md to a self-contained HTML file.
Uses regex-based markdown parsing (no external dependencies).
"""

import re
import html as html_module
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MD_FILE = SCRIPT_DIR / "PHASE1_TECHNICAL_DOCUMENT.md"
HTML_FILE = SCRIPT_DIR / "PHASE1_TECHNICAL_DOCUMENT.html"
