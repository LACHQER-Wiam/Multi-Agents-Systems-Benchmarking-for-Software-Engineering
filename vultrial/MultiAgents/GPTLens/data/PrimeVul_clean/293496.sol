gif_internal_decode_frame(gif_animation *gif,
                          unsigned int frame,
                          bool clear_image)
{
        unsigned int index = 0;
        const unsigned char *gif_data, *gif_end;
        ssize_t gif_bytes;
        unsigned int width, height, offset_x, offset_y;
        unsigned int flags, colour_table_size, interlace;
        unsigned int *colour_table;
        unsigned int *frame_data = 0;	
        unsigned int *frame_scanline;
        ssize_t save_buffer_position;
        unsigned int return_value = 0;
        unsigned int x, y, decode_y, burst_bytes;
        register unsigned char colour;
        if (gif->frames == NULL) {
                return GIF_INSUFFICIENT_DATA;
        }
        if (gif->frames[frame].display == false) {
                return GIF_OK;
        }
        if (frame > gif->frame_count_partial) {
                return GIF_INSUFFICIENT_DATA;
        }
        if ((!clear_image) &&
            ((int)frame == gif->decoded_frame)) {
                return GIF_OK;
        }
        gif_data = gif->gif_data + gif->frames[frame].frame_pointer;
        gif_end = gif->gif_data + gif->buffer_size;
        gif_bytes = (gif_end - gif_data);
        if (gif_bytes < 12) {
                return GIF_INSUFFICIENT_FRAME_DATA;
        }
        save_buffer_position = gif->buffer_position;
        gif->buffer_position = gif_data - gif->gif_data;
        if ((return_value = gif_skip_frame_extensions(gif)) != GIF_OK) {
                goto gif_decode_frame_exit;
        }
        gif_data = (gif->gif_data + gif->buffer_position);
        gif_bytes = (gif_end - gif_data);
        if (gif_bytes < 12) {
                return_value = GIF_INSUFFICIENT_FRAME_DATA;
                goto gif_decode_frame_exit;
        }
        if (gif_data[0] != GIF_IMAGE_SEPARATOR) {
                return_value = GIF_DATA_ERROR;
                goto gif_decode_frame_exit;
        }
        offset_x = gif_data[1] | (gif_data[2] << 8);
        offset_y = gif_data[3] | (gif_data[4] << 8);
        width = gif_data[5] | (gif_data[6] << 8);
        height = gif_data[7] | (gif_data[8] << 8);
        if ((offset_x + width > gif->width) ||
            (offset_y + height > gif->height)) {
                return_value = GIF_DATA_ERROR;
                goto gif_decode_frame_exit;
        }
        flags = gif_data[9];
        colour_table_size = 2 << (flags & GIF_COLOUR_TABLE_SIZE_MASK);
        interlace = flags & GIF_INTERLACE_MASK;
        gif_data += 10;
        gif_bytes = (gif_end - gif_data);
        if (flags & GIF_COLOUR_TABLE_MASK) {
                if (gif_bytes < (int)(3 * colour_table_size)) {
                        return_value = GIF_INSUFFICIENT_FRAME_DATA;
                        goto gif_decode_frame_exit;
                }
                colour_table = gif->local_colour_table;
                if (!clear_image) {
                        for (index = 0; index < colour_table_size; index++) {
                                unsigned char *entry =
                                        (unsigned char *) &colour_table[index];
                                entry[0] = gif_data[0];	
                                entry[1] = gif_data[1];	
                                entry[2] = gif_data[2];	
                                entry[3] = 0xff;	
                                gif_data += 3;
                        }
                } else {
                        gif_data += 3 * colour_table_size;
                }
                gif_bytes = (gif_end - gif_data);
        } else {
                colour_table = gif->global_colour_table;
        }
        if (gif_bytes < 1) {
                return_value = GIF_INSUFFICIENT_FRAME_DATA;
                goto gif_decode_frame_exit;
        }
        if (gif_data[0] == GIF_TRAILER) {
                return_value = GIF_OK;
                goto gif_decode_frame_exit;
        }
        assert(gif->bitmap_callbacks.bitmap_get_buffer);
        frame_data = (void *)gif->bitmap_callbacks.bitmap_get_buffer(gif->frame_image);
        if (!frame_data) {
                return GIF_INSUFFICIENT_MEMORY;
        }
        if (!clear_image) {
                lzw_result res;
                const uint8_t *stack_base;
                const uint8_t *stack_pos;
                if (gif_bytes < 2) {
                        return_value = GIF_INSUFFICIENT_FRAME_DATA;
                        goto gif_decode_frame_exit;
                }
                if ((gif_bytes == 2) && (gif_data[1] == GIF_TRAILER)) {
                        return_value = GIF_OK;
                        goto gif_decode_frame_exit;
                }
                if ((frame == 0) || (gif->decoded_frame == GIF_INVALID_FRAME)) {
                        memset((char*)frame_data,
                               GIF_TRANSPARENT_COLOUR,
                               gif->width * gif->height * sizeof(int));
                        gif->decoded_frame = frame;
                } else if ((frame != 0) &&
                           (gif->frames[frame - 1].disposal_method == GIF_FRAME_CLEAR)) {
                        return_value = gif_internal_decode_frame(gif,
                                                                 (frame - 1),
                                                                 true);
                        if (return_value != GIF_OK) {
                                goto gif_decode_frame_exit;
                        }
                } else if ((frame != 0) &&
                           (gif->frames[frame - 1].disposal_method == GIF_FRAME_RESTORE)) {
                        int last_undisposed_frame = frame - 2;
                        while ((last_undisposed_frame >= 0) &&
                               (gif->frames[last_undisposed_frame].disposal_method == GIF_FRAME_RESTORE)) {
                                last_undisposed_frame--;
                        }
                        if (last_undisposed_frame == -1) {
                                memset((char*)frame_data,
                                       GIF_TRANSPARENT_COLOUR,
                                       gif->width * gif->height * sizeof(int));
                        } else {
                                return_value = gif_internal_decode_frame(gif, last_undisposed_frame, false);
                                if (return_value != GIF_OK) {
                                        goto gif_decode_frame_exit;
                                }
                                assert(gif->bitmap_callbacks.bitmap_get_buffer);
                                frame_data = (void *)gif->bitmap_callbacks.bitmap_get_buffer(gif->frame_image);
                                if (!frame_data) {
                                        return GIF_INSUFFICIENT_MEMORY;
                                }
                        }
                }
                gif->decoded_frame = frame;
                gif->buffer_position = (gif_data - gif->gif_data) + 1;
                res = lzw_decode_init(gif->lzw_ctx, gif->gif_data,
                                gif->buffer_size, gif->buffer_position,
                                gif_data[0], &stack_base, &stack_pos);
                if (res != LZW_OK) {
                        return gif_error_from_lzw(res);
                }
                for (y = 0; y < height; y++) {
                        if (interlace) {
                                decode_y = gif_interlaced_line(height, y) + offset_y;
                        } else {
                                decode_y = y + offset_y;
                        }
                        frame_scanline = frame_data + offset_x + (decode_y * gif->width);
                        x = width;
                        while (x > 0) {
                                burst_bytes = (stack_pos - stack_base);
                                if (burst_bytes > 0) {
                                        if (burst_bytes > x) {
                                                burst_bytes = x;
                                        }
                                        x -= burst_bytes;
                                        while (burst_bytes-- > 0) {
                                                colour = *--stack_pos;
                                                if (((gif->frames[frame].transparency) &&
                                                     (colour != gif->frames[frame].transparency_index)) ||
                                                    (!gif->frames[frame].transparency)) {
                                                        *frame_scanline = colour_table[colour];
                                                }
                                                frame_scanline++;
                                        }
                                } else {
                                        res = lzw_decode(gif->lzw_ctx, &stack_pos);
                                        if (res != LZW_OK) {
                                                if (res == LZW_OK_EOD) {
                                                        return_value = GIF_OK;
                                                } else {
                                                        return_value = gif_error_from_lzw(res);
                                                }
                                                goto gif_decode_frame_exit;
                                        }
                                }
                        }
                }
        } else {
                if (gif->frames[frame].disposal_method == GIF_FRAME_CLEAR) {
                        for (y = 0; y < height; y++) {
                                frame_scanline = frame_data + offset_x + ((offset_y + y) * gif->width);
                                if (gif->frames[frame].transparency) {
                                        memset(frame_scanline,
                                               GIF_TRANSPARENT_COLOUR,
                                               width * 4);
                                } else {
                                        memset(frame_scanline,
                                               colour_table[gif->background_index],
                                               width * 4);
                                }
                        }
                }
        }
gif_decode_frame_exit:
        if (gif->frames[frame].virgin) {
                if (gif->bitmap_callbacks.bitmap_test_opaque) {
                        gif->frames[frame].opaque = gif->bitmap_callbacks.bitmap_test_opaque(gif->frame_image);
                } else {
                        gif->frames[frame].opaque = false;
                }
                gif->frames[frame].virgin = false;
        }
        if (gif->bitmap_callbacks.bitmap_set_opaque) {
                gif->bitmap_callbacks.bitmap_set_opaque(gif->frame_image, gif->frames[frame].opaque);
        }
        if (gif->bitmap_callbacks.bitmap_modified) {
                gif->bitmap_callbacks.bitmap_modified(gif->frame_image);
        }
        gif->buffer_position = save_buffer_position;
        return return_value;
}