static Image *ReadMATImage(const ImageInfo *image_info,ExceptionInfo *exception)
{
  Image *image, *image2=NULL,
   *rotated_image;
  register Quantum *q;
  unsigned int status;
  MATHeader MATLAB_HDR;
  size_t size;  
  size_t CellType;
  QuantumInfo *quantum_info;
  ImageInfo *clone_info;
  int i;
  ssize_t ldblk;
  unsigned char *BImgBuff = NULL;
  double MinVal, MaxVal;
  unsigned z, z2;
  unsigned Frames;
  int logging;
  int sample_size;
  MagickOffsetType filepos=0x80;
  BlobInfo *blob;
  size_t one;
  unsigned int (*ReadBlobXXXLong)(Image *image);
  unsigned short (*ReadBlobXXXShort)(Image *image);
  void (*ReadBlobDoublesXXX)(Image * image, size_t len, double *data);
  void (*ReadBlobFloatsXXX)(Image * image, size_t len, float *data);
  assert(image_info != (const ImageInfo *) NULL);
  assert(image_info->signature == MagickCoreSignature);
  assert(exception != (ExceptionInfo *) NULL);
  assert(exception->signature == MagickCoreSignature);
  logging = LogMagickEvent(CoderEvent,GetMagickModule(),"enter"); 
  image = AcquireImage(image_info,exception);
  status = OpenBlob(image_info, image, ReadBinaryBlobMode, exception);
  if (status == MagickFalse)
    {
      image=DestroyImageList(image);
      return((Image *) NULL);
    }
  clone_info=CloneImageInfo(image_info);
  if(ReadBlob(image,124,(unsigned char *) &MATLAB_HDR.identific) != 124)
    ThrowReaderException(CorruptImageError,"ImproperImageHeader");
  MATLAB_HDR.Version = ReadBlobLSBShort(image);
  if(ReadBlob(image,2,(unsigned char *) &MATLAB_HDR.EndianIndicator) != 2)
    ThrowReaderException(CorruptImageError,"ImproperImageHeader");
  if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),"  Endian %c%c",
        MATLAB_HDR.EndianIndicator[0],MATLAB_HDR.EndianIndicator[1]);
  if (!strncmp(MATLAB_HDR.EndianIndicator, "IM", 2))
  {
    ReadBlobXXXLong = ReadBlobLSBLong;
    ReadBlobXXXShort = ReadBlobLSBShort;
    ReadBlobDoublesXXX = ReadBlobDoublesLSB;
    ReadBlobFloatsXXX = ReadBlobFloatsLSB;
    image->endian = LSBEndian;
  } 
  else if (!strncmp(MATLAB_HDR.EndianIndicator, "MI", 2))
  {
    ReadBlobXXXLong = ReadBlobMSBLong;
    ReadBlobXXXShort = ReadBlobMSBShort;
    ReadBlobDoublesXXX = ReadBlobDoublesMSB;
    ReadBlobFloatsXXX = ReadBlobFloatsMSB;
    image->endian = MSBEndian;
  }
  else 
    goto MATLAB_KO;    
  if (strncmp(MATLAB_HDR.identific, "MATLAB", 6))
MATLAB_KO: ThrowReaderException(CorruptImageError,"ImproperImageHeader");
  filepos = TellBlob(image);
  while(!EOFBlob(image)) 
  {
    Frames = 1;
    (void) SeekBlob(image,filepos,SEEK_SET);
    MATLAB_HDR.DataType = ReadBlobXXXLong(image);
    if(EOFBlob(image)) break;
    MATLAB_HDR.ObjectSize = ReadBlobXXXLong(image);
    if(EOFBlob(image)) break;
    filepos += MATLAB_HDR.ObjectSize + 4 + 4;
    image2 = image;
#if defined(MAGICKCORE_ZLIB_DELEGATE)
    if(MATLAB_HDR.DataType == miCOMPRESSED)
    {
      image2 = DecompressBlock(image,MATLAB_HDR.ObjectSize,clone_info,exception);
      if(image2==NULL) continue;
      MATLAB_HDR.DataType = ReadBlobXXXLong(image2); 
    }
#endif    
    if(MATLAB_HDR.DataType!=miMATRIX) continue;  
    MATLAB_HDR.unknown1 = ReadBlobXXXLong(image2);
    MATLAB_HDR.unknown2 = ReadBlobXXXLong(image2);  
    MATLAB_HDR.unknown5 = ReadBlobXXXLong(image2);
    MATLAB_HDR.StructureClass = MATLAB_HDR.unknown5 & 0xFF;
    MATLAB_HDR.StructureFlag = (MATLAB_HDR.unknown5>>8) & 0xFF;  
    MATLAB_HDR.unknown3 = ReadBlobXXXLong(image2);
    if(image!=image2)
      MATLAB_HDR.unknown4 = ReadBlobXXXLong(image2);  
    MATLAB_HDR.unknown4 = ReadBlobXXXLong(image2);
    MATLAB_HDR.DimFlag = ReadBlobXXXLong(image2);
    MATLAB_HDR.SizeX = ReadBlobXXXLong(image2);
    MATLAB_HDR.SizeY = ReadBlobXXXLong(image2);  
    switch(MATLAB_HDR.DimFlag)
    {     
      case  8: z2=z=1; break;      
      case 12: z2=z = ReadBlobXXXLong(image2);  
           (void) ReadBlobXXXLong(image2);
         if(z!=3) ThrowReaderException(CoderError, "MultidimensionalMatricesAreNotSupported");
         break;
      case 16: z2=z = ReadBlobXXXLong(image2);  
         if(z!=3 && z!=1)
            ThrowReaderException(CoderError, "MultidimensionalMatricesAreNotSupported");
           Frames = ReadBlobXXXLong(image2);
         break;
      default: ThrowReaderException(CoderError, "MultidimensionalMatricesAreNotSupported");
    }  
    MATLAB_HDR.Flag1 = ReadBlobXXXShort(image2);
    MATLAB_HDR.NameFlag = ReadBlobXXXShort(image2);
    if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),
          "MATLAB_HDR.StructureClass %d",MATLAB_HDR.StructureClass);
    if (MATLAB_HDR.StructureClass != mxCHAR_CLASS && 
        MATLAB_HDR.StructureClass != mxSINGLE_CLASS &&    
        MATLAB_HDR.StructureClass != mxDOUBLE_CLASS &&    
        MATLAB_HDR.StructureClass != mxINT8_CLASS &&
        MATLAB_HDR.StructureClass != mxUINT8_CLASS &&    
        MATLAB_HDR.StructureClass != mxINT16_CLASS &&
        MATLAB_HDR.StructureClass != mxUINT16_CLASS &&    
        MATLAB_HDR.StructureClass != mxINT32_CLASS &&
        MATLAB_HDR.StructureClass != mxUINT32_CLASS &&    
        MATLAB_HDR.StructureClass != mxINT64_CLASS &&
        MATLAB_HDR.StructureClass != mxUINT64_CLASS)    
      ThrowReaderException(CoderError,"UnsupportedCellTypeInTheMatrix");
    switch (MATLAB_HDR.NameFlag)
    {
      case 0:
        size = ReadBlobXXXLong(image2);  
        size = 4 * (ssize_t) ((size + 3 + 1) / 4);
        (void) SeekBlob(image2, size, SEEK_CUR);
        break;
      case 1:
      case 2:
      case 3:
      case 4:
        (void) ReadBlob(image2, 4, (unsigned char *) &size); 
        break;
      default:
        goto MATLAB_KO;
    }
    CellType = ReadBlobXXXLong(image2);    
    if (logging)
      (void) LogMagickEvent(CoderEvent,GetMagickModule(),
        "MATLAB_HDR.CellType: %.20g",(double) CellType);
    (void) ReadBlob(image2, 4, (unsigned char *) &size);     
    NEXT_FRAME:
    switch (CellType)
    {
      case miINT8:
      case miUINT8:
        sample_size = 8;
        if(MATLAB_HDR.StructureFlag & FLAG_LOGICAL) 
          image->depth = 1;
        else
          image->depth = 8;         
        ldblk = (ssize_t) MATLAB_HDR.SizeX;      
        break;
      case miINT16:
      case miUINT16:
        sample_size = 16;
        image->depth = 16;        
        ldblk = (ssize_t) (2 * MATLAB_HDR.SizeX);
        break;
      case miINT32:
      case miUINT32:
        sample_size = 32;
        image->depth = 32;        
        ldblk = (ssize_t) (4 * MATLAB_HDR.SizeX);      
        break;
      case miINT64:
      case miUINT64:
        sample_size = 64;
        image->depth = 64;        
        ldblk = (ssize_t) (8 * MATLAB_HDR.SizeX);      
        break;   
      case miSINGLE:
        sample_size = 32;
        image->depth = 32;        
        (void) SetImageOption(clone_info,"quantum:format","floating-point");
        if (MATLAB_HDR.StructureFlag & FLAG_COMPLEX)
  {              
  }
        ldblk = (ssize_t) (4 * MATLAB_HDR.SizeX);
        break;
      case miDOUBLE:
        sample_size = 64; 
        image->depth = 64;        
        (void) SetImageOption(clone_info,"quantum:format","floating-point");
DisableMSCWarning(4127)
        if (sizeof(double) != 8)
RestoreMSCWarning
          ThrowReaderException(CoderError, "IncompatibleSizeOfDouble");
        if (MATLAB_HDR.StructureFlag & FLAG_COMPLEX)
  {                                 
  }
        ldblk = (ssize_t) (8 * MATLAB_HDR.SizeX);
        break;
      default:
        ThrowReaderException(CoderError, "UnsupportedCellTypeInTheMatrix");
    }
    (void) sample_size;
    image->columns = MATLAB_HDR.SizeX;
    image->rows = MATLAB_HDR.SizeY;    
    quantum_info=AcquireQuantumInfo(clone_info,image);
    if (quantum_info == (QuantumInfo *) NULL)
      ThrowReaderException(ResourceLimitError,"MemoryAllocationFailed");
    one=1;
    image->colors = one << image->depth;
    if (image->columns == 0 || image->rows == 0)
      goto MATLAB_KO;
    if ((MATLAB_HDR.DimFlag == 8) &&
        ((MATLAB_HDR.StructureFlag & FLAG_COMPLEX) == 0))
      {
        image->type=GrayscaleType;
        SetImageColorspace(image,GRAYColorspace,exception);
      }
    if (image_info->ping)
    {
      size_t temp = image->columns;
      image->columns = image->rows;
      image->rows = temp;
      goto done_reading; 
    }  
    status=SetImageExtent(image,image->columns,image->rows,exception);
    if (status == MagickFalse)
      return(DestroyImageList(image));
    BImgBuff = (unsigned char *) AcquireQuantumMemory((size_t) (ldblk),sizeof(double));    
    if (BImgBuff == NULL)
      ThrowReaderException(ResourceLimitError,"MemoryAllocationFailed");
    MinVal = 0;
    MaxVal = 0;
    if (CellType==miDOUBLE || CellType==miSINGLE)        
    {
      CalcMinMax(image2, image_info->endian,  MATLAB_HDR.SizeX, MATLAB_HDR.SizeY, CellType, ldblk, BImgBuff, &quantum_info->minimum, &quantum_info->maximum);
    }
    if(z==1) z=0; 
    do
    {
      for (i = 0; i < (ssize_t) MATLAB_HDR.SizeY; i++)
      {
        q=GetAuthenticPixels(image,0,MATLAB_HDR.SizeY-i-1,image->columns,1,exception);
        if (q == (Quantum *) NULL)
  {
    if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),
              "  MAT set image pixels returns unexpected NULL on a row %u.", (unsigned)(MATLAB_HDR.SizeY-i-1));
    goto done_reading;    
  }
        if(ReadBlob(image2,ldblk,(unsigned char *)BImgBuff) != (ssize_t) ldblk)
  {
    if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),
             "  MAT cannot read scanrow %u from a file.", (unsigned)(MATLAB_HDR.SizeY-i-1));
    goto ExitLoop;
  }
        if((CellType==miINT8 || CellType==miUINT8) && (MATLAB_HDR.StructureFlag & FLAG_LOGICAL))
        {
          FixLogical((unsigned char *)BImgBuff,ldblk);
          if(ImportQuantumPixels(image,(CacheView *) NULL,quantum_info,z2qtype[z],BImgBuff,exception) <= 0)
    {
ImportQuantumPixelsFailed:
      if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),
              "  MAT failed to ImportQuantumPixels for a row %u", (unsigned)(MATLAB_HDR.SizeY-i-1));
      break;
    }
        }
        else
        {
          if(ImportQuantumPixels(image,(CacheView *) NULL,quantum_info,z2qtype[z],BImgBuff,exception) <= 0)
      goto ImportQuantumPixelsFailed;
          if (z<=1 &&       
          (CellType==miINT8 || CellType==miINT16 || CellType==miINT32 || CellType==miINT64))
      FixSignedValues(image,q,MATLAB_HDR.SizeX);
        }
        if (!SyncAuthenticPixels(image,exception))
  {
    if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),
            "  MAT failed to sync image pixels for a row %u", (unsigned)(MATLAB_HDR.SizeY-i-1));
    goto ExitLoop;
  }
      }
    } while(z-- >= 2);
    quantum_info=DestroyQuantumInfo(quantum_info);
ExitLoop:
    if (MATLAB_HDR.StructureFlag & FLAG_COMPLEX)
    {        
      CellType = ReadBlobXXXLong(image2);    
      i = ReadBlobXXXLong(image2);           
      if (CellType==miDOUBLE || CellType==miSINGLE)
      {
        CalcMinMax(image2,  image_info->endian, MATLAB_HDR.SizeX, MATLAB_HDR.SizeY, CellType, ldblk, BImgBuff, &MinVal, &MaxVal);      
      }
      if (CellType==miDOUBLE)
        for (i = 0; i < (ssize_t) MATLAB_HDR.SizeY; i++)
  {
          ReadBlobDoublesXXX(image2, ldblk, (double *)BImgBuff);
          InsertComplexDoubleRow(image, (double *)BImgBuff, i, MinVal, MaxVal,
            exception);
  }
      if (CellType==miSINGLE)
        for (i = 0; i < (ssize_t) MATLAB_HDR.SizeY; i++)
  {
          ReadBlobFloatsXXX(image2, ldblk, (float *)BImgBuff);
          InsertComplexFloatRow(image,(float *)BImgBuff,i,MinVal,MaxVal,
            exception);
  }    
    }
    if ((MATLAB_HDR.DimFlag == 8) &&
        ((MATLAB_HDR.StructureFlag & FLAG_COMPLEX) == 0))
      image->type=GrayscaleType;
    if (image->depth == 1)
      image->type=BilevelType;
    if(image2==image)
        image2 = NULL;    
    rotated_image = RotateImage(image, 90.0, exception);
    if (rotated_image != (Image *) NULL)
    {
      rotated_image->page.x=0;
      rotated_image->page.y=0;
      blob = rotated_image->blob;
      rotated_image->blob = image->blob;
      rotated_image->colors = image->colors;
      image->blob = blob;
      AppendImageToList(&image,rotated_image);      
      DeleteImageFromList(&image);      
    }
done_reading:
    if(image2!=NULL)
      if(image2!=image)
      {
        DeleteImageFromList(&image2); 
  if(clone_info)
  {
          if(clone_info->file)
    {
            fclose(clone_info->file);
            clone_info->file = NULL;
            (void) remove_utf8(clone_info->filename);
    }
        }    
      }
    AcquireNextImage(image_info,image,exception);
    if (image->next == (Image *) NULL) break;                
    image=SyncNextImageInList(image);
    image->columns=image->rows=0;
    image->colors=0;    
    RelinquishMagickMemory(BImgBuff);
    BImgBuff = NULL;
    if(--Frames>0)
    {
      z = z2;
      if(image2==NULL) image2 = image;
      goto NEXT_FRAME;
    }
    if ((image2!=NULL) && (image2!=image))   
      {
        DeleteImageFromList(&image2);
        if(clone_info)
        {
          if(clone_info->file)
          {
            fclose(clone_info->file);
            clone_info->file = NULL;
            (void) remove_utf8(clone_info->filename);
          }
        }
        }
  }
  clone_info=DestroyImageInfo(clone_info);
  RelinquishMagickMemory(BImgBuff);
  CloseBlob(image);
  {
    Image *p;    
    ssize_t scene=0;
    p=image;
    image=NULL;
    while (p != (Image *) NULL)
      {
        Image *tmp=p;
        if ((p->rows == 0) || (p->columns == 0)) {
          p=p->previous;
          DeleteImageFromList(&tmp);
        } else {
          image=p;
          p=p->previous;
        }
      }
    for (p=image; p != (Image *) NULL; p=p->next)
      p->scene=scene++;
  }
  if(clone_info != NULL)  
  {
    if(clone_info->file)
    {
      fclose(clone_info->file);
      clone_info->file = NULL;
      (void) remove_utf8(clone_info->filename);
    }
    DestroyImageInfo(clone_info);
    clone_info = NULL;
  }
  if (logging) (void)LogMagickEvent(CoderEvent,GetMagickModule(),"return");
  if(image==NULL)
    ThrowReaderException(CorruptImageError,"ImproperImageHeader");
  return (image);
}