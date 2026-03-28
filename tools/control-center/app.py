"""Main window with sidebar navigation."""

from PySide6.QtWidgets import (
    QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
    QListWidget, QListWidgetItem, QStackedWidget, QLabel,
)
from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QIcon, QFont

from track_manager import TrackManagerWidget
from geology_manager import GeologyManagerWidget


class ControlCenter(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MapsPersonal — Control Center")
        self.setMinimumSize(1200, 700)
        self.resize(1400, 800)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Sidebar
        self.sidebar = QListWidget()
        self.sidebar.setFixedWidth(200)
        self.sidebar.setIconSize(QSize(20, 20))
        self.sidebar.setFont(QFont("", 13))
        self.sidebar.setStyleSheet("""
            QListWidget {
                background-color: #2b2b2b;
                color: #e0e0e0;
                border: none;
                padding: 8px;
            }
            QListWidget::item {
                padding: 12px 8px;
                border-radius: 6px;
                margin: 2px 0;
            }
            QListWidget::item:selected {
                background-color: #3d5afe;
                color: white;
            }
            QListWidget::item:hover:!selected {
                background-color: #3a3a3a;
            }
        """)

        # Modules
        self.modules = []
        self._add_module("Tracks", TrackManagerWidget())
        self._add_module("HR Zones", self._placeholder("HR Zone Analysis", "Coming soon..."))
        self._add_module("Maps", self._placeholder("Map Manager", "Download and manage offline maps"))
        self._add_module("Geology", GeologyManagerWidget())

        # Content area
        self.stack = QStackedWidget()
        for _, widget in self.modules:
            self.stack.addWidget(widget)

        self.sidebar.currentRowChanged.connect(self.stack.setCurrentIndex)
        self.sidebar.setCurrentRow(0)

        layout.addWidget(self.sidebar)
        layout.addWidget(self.stack, 1)

    def _add_module(self, name: str, widget: QWidget):
        item = QListWidgetItem(name)
        self.sidebar.addItem(item)
        self.modules.append((name, widget))

    def _placeholder(self, title: str, subtitle: str) -> QWidget:
        w = QWidget()
        layout = QVBoxLayout(w)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        title_label = QLabel(title)
        title_label.setFont(QFont("", 24, QFont.Weight.Bold))
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title_label.setStyleSheet("color: #888;")

        sub_label = QLabel(subtitle)
        sub_label.setFont(QFont("", 14))
        sub_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        sub_label.setStyleSheet("color: #666;")

        layout.addWidget(title_label)
        layout.addWidget(sub_label)
        return w
