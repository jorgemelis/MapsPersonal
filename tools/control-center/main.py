#!/usr/bin/env python3
"""MapsPersonal Control Center — Desktop companion app."""

import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication
from PySide6.QtCore import Qt

from app import ControlCenter


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("MapsPersonal")
    app.setOrganizationName("MapsPersonal")

    # Dark/light follows system
    app.setStyle("Fusion")

    window = ControlCenter()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
