void gdImageFillToBorder (gdImagePtr im, int x, int y, int border, int color)
{
	int lastBorder;
	int leftLimit = -1, rightLimit;
	int i;
	if (border < 0) {
		return;
	}
	if (x >= im->sx) {
		x = im->sx - 1;
	}
	if (y >= im->sy) {
		y = im->sy - 1;
	}
	for (i = x; i >= 0; i--) {
		if (gdImageGetPixel(im, i, y) == border) {
			break;
		}
		gdImageSetPixel(im, i, y, color);
		leftLimit = i;
	}
	if (leftLimit == -1) {
		return;
	}
	rightLimit = x;
	for (i = (x + 1); i < im->sx; i++) {
		if (gdImageGetPixel(im, i, y) == border) {
			break;
		}
		gdImageSetPixel(im, i, y, color);
		rightLimit = i;
	}
	if (y > 0) {
		lastBorder = 1;
		for (i = leftLimit; i <= rightLimit; i++) {
			int c = gdImageGetPixel(im, i, y - 1);
			if (lastBorder) {
				if ((c != border) && (c != color)) {
					gdImageFillToBorder(im, i, y - 1, border, color);
					lastBorder = 0;
				}
			} else if ((c == border) || (c == color)) {
				lastBorder = 1;
			}
		}
	}
	if (y < ((im->sy) - 1)) {
		lastBorder = 1;
		for (i = leftLimit; i <= rightLimit; i++) {
			int c = gdImageGetPixel(im, i, y + 1);
			if (lastBorder) {
				if ((c != border) && (c != color)) {
					gdImageFillToBorder(im, i, y + 1, border, color);
					lastBorder = 0;
				}
			} else if ((c == border) || (c == color)) {
				lastBorder = 1;
			}
		}
	}
}