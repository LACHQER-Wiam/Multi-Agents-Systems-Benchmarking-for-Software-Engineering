void DecodePngV2(OpKernelContext* context, StringPiece input) {
    int channel_bits = (data_type_ == DataType::DT_UINT8) ? 8 : 16;
    png::DecodeContext decode;
    OP_REQUIRES(
        context, png::CommonInitDecode(input, channels_, channel_bits, &decode),
        errors::InvalidArgument("Invalid PNG. Failed to initialize decoder."));
    const int width = static_cast<int>(decode.width);
    const int height = static_cast<int>(decode.height);
    const int64_t total_size =
        static_cast<int64_t>(width) * static_cast<int64_t>(height);
    if (width != static_cast<int64_t>(decode.width) || width <= 0 ||
        width >= (1LL << 27) || height != static_cast<int64_t>(decode.height) ||
        height <= 0 || height >= (1LL << 27) || total_size >= (1LL << 29)) {
      png::CommonFreeDecode(&decode);
      OP_REQUIRES(context, false,
                  errors::InvalidArgument("PNG size too large for int: ",
                                          decode.width, " by ", decode.height));
    }
    Tensor* output = nullptr;
    Status status;
    if (op_type_ == "DecodeGif") {
      status = context->allocate_output(
          0, TensorShape({1, height, width, decode.channels}), &output);
    } else {
      status = context->allocate_output(
          0, TensorShape({height, width, decode.channels}), &output);
    }
    if (op_type_ == "DecodeBmp") {
      OP_REQUIRES(context, false,
                  errors::InvalidArgument(
                      "Trying to decode PNG format using DecodeBmp op. Use "
                      "`decode_png` or `decode_image` instead."));
    } else if (op_type_ == "DecodeAndCropJpeg") {
      OP_REQUIRES(context, false,
                  errors::InvalidArgument(
                      "DecodeAndCropJpeg operation can run on JPEG only, but "
                      "detected PNG."));
    }
    if (!status.ok()) png::CommonFreeDecode(&decode);
    OP_REQUIRES_OK(context, status);
    if (data_type_ == DataType::DT_UINT8) {
      OP_REQUIRES(
          context,
          png::CommonFinishDecode(
              reinterpret_cast<png_bytep>(output->flat<uint8>().data()),
              decode.channels * width * sizeof(uint8), &decode),
          errors::InvalidArgument("Invalid PNG data, size ", input.size()));
    } else if (data_type_ == DataType::DT_UINT16) {
      OP_REQUIRES(
          context,
          png::CommonFinishDecode(
              reinterpret_cast<png_bytep>(output->flat<uint16>().data()),
              decode.channels * width * sizeof(uint16), &decode),
          errors::InvalidArgument("Invalid PNG data, size ", input.size()));
    } else if (data_type_ == DataType::DT_FLOAT) {
      std::unique_ptr<uint16[]> buffer(
          new uint16[height * width * decode.channels]);
      OP_REQUIRES(
          context,
          png::CommonFinishDecode(reinterpret_cast<png_bytep>(buffer.get()),
                                  decode.channels * width * sizeof(uint16),
                                  &decode),
          errors::InvalidArgument("Invalid PNG data, size ", input.size()));
      const auto& device = context->eigen_device<Eigen::ThreadPoolDevice>();
      TTypes<uint16, 3>::UnalignedConstTensor buf(buffer.get(), height, width,
                                                  decode.channels);
      float scale = 1. / std::numeric_limits<uint16>::max();
      output->tensor<float, 3>().device(device) = buf.cast<float>() * scale;
    }
  }