"""Image Cropper — interactive crop tool for geological map legends.

Opens a JPG/PNG in a scrollable view with a draggable rectangle.
User draws a selection, then saves the cropped region.
Cross-platform (PySide6).
"""

from pathlib import Path

from PySide6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QLabel,
    QScrollArea, QFileDialog, QApplication,
)
from PySide6.QtCore import Qt, QRect, QPoint, Signal
from PySide6.QtGui import QPixmap, QPainter, QPen, QColor, QImage


class CropLabel(QLabel):
    """QLabel that allows drawing a crop rectangle with the mouse."""

    crop_changed = Signal(QRect)

    def __init__(self):
        super().__init__()
        self._pixmap = None
        self._crop_rect = QRect()
        self._drawing = False
        self._start = QPoint()
        self._moving = False
        self._move_offset = QPoint()
        self.setCursor(Qt.CursorShape.CrossCursor)

    def set_image(self, pixmap: QPixmap):
        self._pixmap = pixmap
        self.setFixedSize(pixmap.size())
        self._crop_rect = QRect()
        self.update()

    def get_crop_rect(self) -> QRect:
        return self._crop_rect

    def paintEvent(self, event):
        if not self._pixmap:
            return
        painter = QPainter(self)
        painter.drawPixmap(0, 0, self._pixmap)

        if not self._crop_rect.isNull():
            # Dim outside selection
            overlay = QColor(0, 0, 0, 100)
            full = self.rect()
            cr = self._crop_rect.normalized()

            # Top
            painter.fillRect(QRect(full.left(), full.top(), full.width(), cr.top()), overlay)
            # Bottom
            painter.fillRect(QRect(full.left(), cr.bottom() + 1, full.width(), full.bottom() - cr.bottom()), overlay)
            # Left
            painter.fillRect(QRect(full.left(), cr.top(), cr.left(), cr.height()), overlay)
            # Right
            painter.fillRect(QRect(cr.right() + 1, cr.top(), full.right() - cr.right(), cr.height()), overlay)

            # Selection border
            pen = QPen(QColor(255, 80, 80), 2, Qt.PenStyle.DashLine)
            painter.setPen(pen)
            painter.drawRect(cr)

            # Size label
            painter.setPen(QColor(255, 255, 255))
            painter.drawText(cr.left() + 4, cr.top() - 4,
                           f"{cr.width()} × {cr.height()}")

        painter.end()

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            pos = event.position().toPoint()
            # If clicking inside existing rect, start moving
            if not self._crop_rect.isNull() and self._crop_rect.normalized().contains(pos):
                self._moving = True
                self._move_offset = pos - self._crop_rect.normalized().topLeft()
            else:
                # Start new selection
                self._drawing = True
                self._start = pos
                self._crop_rect = QRect(pos, pos)
            self.update()

    def mouseMoveEvent(self, event):
        pos = event.position().toPoint()
        if self._drawing:
            self._crop_rect = QRect(self._start, pos)
            self.update()
        elif self._moving:
            rect = self._crop_rect.normalized()
            new_tl = pos - self._move_offset
            # Clamp to image bounds
            new_tl.setX(max(0, min(new_tl.x(), self.width() - rect.width())))
            new_tl.setY(max(0, min(new_tl.y(), self.height() - rect.height())))
            self._crop_rect = QRect(new_tl, rect.size())
            self.update()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            if self._drawing:
                self._drawing = False
                self._crop_rect = self._crop_rect.normalized()
                self.crop_changed.emit(self._crop_rect)
            elif self._moving:
                self._moving = False
            self.update()


class ImageCropperDialog(QDialog):
    """Dialog for viewing and cropping geological map images."""

    def __init__(self, image_path: Path, parent=None):
        super().__init__(parent)
        self.image_path = image_path
        self.setWindowTitle(f"Legend Cropper — {image_path.name}")
        self.setMinimumSize(900, 700)
        self.resize(1100, 800)

        layout = QVBoxLayout(self)

        # Toolbar
        toolbar = QHBoxLayout()

        self.info_label = QLabel("Draw a rectangle over the legend area")
        self.info_label.setStyleSheet("font-size: 13px; color: #666;")
        toolbar.addWidget(self.info_label, 1)

        self.zoom_in_btn = QPushButton("Zoom +")
        self.zoom_in_btn.clicked.connect(lambda: self._zoom(1.25))
        toolbar.addWidget(self.zoom_in_btn)

        self.zoom_out_btn = QPushButton("Zoom −")
        self.zoom_out_btn.clicked.connect(lambda: self._zoom(0.8))
        toolbar.addWidget(self.zoom_out_btn)

        self.fit_btn = QPushButton("Fit")
        self.fit_btn.clicked.connect(self._fit_to_window)
        toolbar.addWidget(self.fit_btn)

        self.save_btn = QPushButton("Save Crop")
        self.save_btn.setStyleSheet("font-size: 13px; padding: 6px 16px; background: #4CAF50; color: white; border-radius: 4px;")
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self._save_crop)
        toolbar.addWidget(self.save_btn)

        layout.addLayout(toolbar)

        # Scrollable image area
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(False)
        self.scroll.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.crop_label = CropLabel()
        self.crop_label.crop_changed.connect(self._on_crop_changed)
        self.scroll.setWidget(self.crop_label)

        layout.addWidget(self.scroll, 1)

        # Load image
        self._original_pixmap = QPixmap(str(image_path))
        self._scale = 1.0
        self._fit_to_window()

    def _update_image(self):
        scaled = self._original_pixmap.scaled(
            self._original_pixmap.size() * self._scale,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )
        self.crop_label.set_image(scaled)

    def _zoom(self, factor):
        self._scale *= factor
        self._scale = max(0.1, min(5.0, self._scale))
        self._update_image()
        self.info_label.setText(f"Zoom: {self._scale:.0%} — Draw a rectangle over the legend")

    def _fit_to_window(self):
        viewport = self.scroll.viewport().size()
        img_size = self._original_pixmap.size()
        scale_w = viewport.width() / img_size.width()
        scale_h = viewport.height() / img_size.height()
        self._scale = min(scale_w, scale_h, 1.0)
        self._update_image()
        self.info_label.setText(f"Zoom: {self._scale:.0%} — Draw a rectangle over the legend")

    def _on_crop_changed(self, rect):
        if rect.width() > 10 and rect.height() > 10:
            self.save_btn.setEnabled(True)
            self.info_label.setText(
                f"Selection: {rect.width()}×{rect.height()} px — "
                f"Click Save Crop or drag to adjust"
            )
        else:
            self.save_btn.setEnabled(False)

    def _save_crop(self):
        crop_rect = self.crop_label.get_crop_rect()
        if crop_rect.isNull() or crop_rect.width() < 10:
            return

        # Map crop rect back to original image coordinates
        orig_rect = QRect(
            int(crop_rect.x() / self._scale),
            int(crop_rect.y() / self._scale),
            int(crop_rect.width() / self._scale),
            int(crop_rect.height() / self._scale),
        )

        # Clamp to image bounds
        img_rect = self._original_pixmap.rect()
        orig_rect = orig_rect.intersected(img_rect)

        cropped = self._original_pixmap.copy(orig_rect)

        # Default save path: same dir, _legend_crop suffix
        default_name = self.image_path.stem + "_legend_crop.jpg"
        default_path = str(self.image_path.parent / default_name)

        save_path, _ = QFileDialog.getSaveFileName(
            self, "Save Cropped Legend", default_path,
            "JPEG (*.jpg);;PNG (*.png);;All Files (*)"
        )

        if save_path:
            cropped.save(save_path, quality=95)
            self.saved_path = Path(save_path)
            self.accept()


def open_cropper(image_path: Path, parent=None) -> Path | None:
    """Open the image cropper dialog and return the saved crop path."""
    dialog = ImageCropperDialog(image_path, parent)
    dialog.exec()
    return getattr(dialog, "saved_path", None)
