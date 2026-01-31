static int do_i2c_md(struct cmd_tbl *cmdtp, int flag, int argc,
		     char *const argv[])
{
	uint	chip;
	uint	addr, length;
	int alen;
	int	j, nbytes, linebytes;
	int ret;
#if CONFIG_IS_ENABLED(DM_I2C)
	struct udevice *dev;
#endif
	chip   = i2c_dp_last_chip;
	addr   = i2c_dp_last_addr;
	alen   = i2c_dp_last_alen;
	length = i2c_dp_last_length;
	if (argc < 3)
		return CMD_RET_USAGE;
	if ((flag & CMD_FLAG_REPEAT) == 0) {
		chip = hextoul(argv[1], NULL);
		addr = hextoul(argv[2], NULL);
		alen = get_alen(argv[2], DEFAULT_ADDR_LEN);
		if (alen > 3)
			return CMD_RET_USAGE;
		if (argc > 3)
			length = hextoul(argv[3], NULL);
	}
#if CONFIG_IS_ENABLED(DM_I2C)
	ret = i2c_get_cur_bus_chip(chip, &dev);
	if (!ret && alen != -1)
		ret = i2c_set_chip_offset_len(dev, alen);
	if (ret)
		return i2c_report_err(ret, I2C_ERR_READ);
#endif
	nbytes = length;
	do {
		unsigned char	linebuf[DISP_LINE_LEN];
		unsigned char	*cp;
		linebytes = (nbytes > DISP_LINE_LEN) ? DISP_LINE_LEN : nbytes;
#if CONFIG_IS_ENABLED(DM_I2C)
		ret = dm_i2c_read(dev, addr, linebuf, linebytes);
#else
		ret = i2c_read(chip, addr, alen, linebuf, linebytes);
#endif
		if (ret)
			return i2c_report_err(ret, I2C_ERR_READ);
		else {
			printf("%04x:", addr);
			cp = linebuf;
			for (j=0; j<linebytes; j++) {
				printf(" %02x", *cp++);
				addr++;
			}
			puts ("    ");
			cp = linebuf;
			for (j=0; j<linebytes; j++) {
				if ((*cp < 0x20) || (*cp > 0x7e))
					puts (".");
				else
					printf("%c", *cp);
				cp++;
			}
			putc ('\n');
		}
		nbytes -= linebytes;
	} while (nbytes > 0);
	i2c_dp_last_chip   = chip;
	i2c_dp_last_addr   = addr;
	i2c_dp_last_alen   = alen;
	i2c_dp_last_length = length;
	return 0;
}