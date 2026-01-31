int64_t GmfOpenMesh(const char *FilNam, int mod, ...)
{
   int      KwdCod, res, *PtrVer, *PtrDim, err;
   int64_t  MshIdx;
   char     str[ GmfStrSiz ];
   va_list  VarArg;
   GmfMshSct *msh;
   if(!(msh = calloc(1, sizeof(GmfMshSct))))
      return(0);
   MshIdx = (int64_t)msh;
   if( (err = setjmp(msh->err)) != 0)
   {
#ifdef GMFDEBUG
      printf("libMeshb : mesh %p : error %d\n", msh, err);
#endif
      if(msh->hdl != NULL)
         fclose(msh->hdl);
      if(msh->FilDes != 0)
#ifdef GMF_WINDOWS
         _close(msh->FilDes);
#else
         close(msh->FilDes);
#endif
      free(msh);
      return(0);
   }
   if(strlen(FilNam) + 7 >= GmfStrSiz)
      longjmp(msh->err, -4);
   strcpy(msh->FilNam, FilNam);
   msh->mod = mod;
   msh->buf = (void *)msh->DblBuf;
   msh->FltBuf = (void *)msh->DblBuf;
   msh->IntBuf = (void *)msh->DblBuf;
   if(strstr(msh->FilNam, ".meshb"))
      msh->typ |= (Bin | MshFil);
   else if(strstr(msh->FilNam, ".mesh"))
      msh->typ |= (Asc | MshFil);
   else if(strstr(msh->FilNam, ".solb"))
      msh->typ |= (Bin | SolFil);
   else if(strstr(msh->FilNam, ".sol"))
      msh->typ |= (Asc | SolFil);
   else
      longjmp(msh->err, -5);
   if(msh->mod == GmfRead)
   {
      va_start(VarArg, mod);
      PtrVer = va_arg(VarArg, int *);
      PtrDim = va_arg(VarArg, int *);
      va_end(VarArg);
      if(msh->typ & Bin)
      {
#ifdef WITH_GMF_AIO
         msh->FilDes = open(msh->FilNam, OPEN_READ_FLAGS, OPEN_READ_MODE);
         if(msh->FilDes <= 0)
            longjmp(msh->err, -6);
         if(read(msh->FilDes, &msh->cod, WrdSiz) != WrdSiz)
            longjmp(msh->err, -7);
#else
         if(!(msh->hdl = fopen(msh->FilNam, "rb")))
            longjmp(msh->err, -8);
         safe_fread(&msh->cod, WrdSiz, 1, msh->hdl, msh->err);
#endif
         if( (msh->cod != 1) && (msh->cod != 16777216) )
            longjmp(msh->err, -9);
         ScaWrd(msh, (unsigned char *)&msh->ver);
         if( (msh->ver < 1) || (msh->ver > 4) )
            longjmp(msh->err, -10);
         if( (msh->ver >= 3) && (sizeof(int64_t) != 8) )
            longjmp(msh->err, -11);
         ScaWrd(msh, (unsigned char *)&KwdCod);
         if(KwdCod != GmfDimension)
            longjmp(msh->err, -12);
         GetPos(msh);
         ScaWrd(msh, (unsigned char *)&msh->dim);
      }
      else
      {
         if(!(msh->hdl = fopen(msh->FilNam, "rb")))
            longjmp(msh->err, -13);
         do
         {
            res = fscanf(msh->hdl, "%s", str);
         }while( (res != EOF) && strcmp(str, "MeshVersionFormatted") );
         if(res == EOF)
            longjmp(msh->err, -14);
         safe_fscanf(msh->hdl, "%d", &msh->ver, msh->err);
         if( (msh->ver < 1) || (msh->ver > 4) )
            longjmp(msh->err, -15);
         do
         {
            res = fscanf(msh->hdl, "%s", str);
         }while( (res != EOF) && strcmp(str, "Dimension") );
         if(res == EOF)
            longjmp(msh->err, -16);
         safe_fscanf(msh->hdl, "%d", &msh->dim, msh->err);
      }
      if( (msh->dim != 2) && (msh->dim != 3) )
         longjmp(msh->err, -17);
      (*PtrVer) = msh->ver;
      (*PtrDim) = msh->dim;
      if(msh->ver == 1)
         msh->FltSiz = 32;
      else
         msh->FltSiz = 64;
      if(!ScaKwdTab(msh))
         return(0);
      return(MshIdx);
   }
   else if(msh->mod == GmfWrite)
   {
      msh->cod = 1;
      va_start(VarArg, mod);
      msh->ver = va_arg(VarArg, int);
      msh->dim = va_arg(VarArg, int);
      va_end(VarArg);
      if( (msh->ver < 1) || (msh->ver > 4) )
         longjmp(msh->err, -18);
      if( (msh->ver >= 3) && (sizeof(int64_t) != 8) )
         longjmp(msh->err, -19);
      if( (msh->dim != 2) && (msh->dim != 3) )
         longjmp(msh->err, -20);
      if(msh->ver == 1)
         msh->FltSiz = 32;
      else
         msh->FltSiz = 64;
      if(msh->typ & Bin) 
      {
#ifdef WITH_GMF_AIO
         msh->FilDes = open(msh->FilNam, OPEN_WRITE_FLAGS, OPEN_WRITE_MODE);
         if(msh->FilDes <= 0)
            longjmp(msh->err, -21);
#else
         if(!(msh->hdl = fopen(msh->FilNam, "wb")))
            longjmp(msh->err, -22);
#endif
      }
      else if(!(msh->hdl = fopen(msh->FilNam, "wb")))
         longjmp(msh->err, -23);
      if(msh->typ & Asc)
      {
         fprintf(msh->hdl, "%s %d\n\n",
               GmfKwdFmt[ GmfVersionFormatted ][0], msh->ver);
         fprintf(msh->hdl, "%s %d\n",
               GmfKwdFmt[ GmfDimension ][0], msh->dim);
      }
      else
      {
         RecWrd(msh, (unsigned char *)&msh->cod);
         RecWrd(msh, (unsigned char *)&msh->ver);
         GmfSetKwd(MshIdx, GmfDimension, 0);
         RecWrd(msh, (unsigned char *)&msh->dim);
      }
      return(MshIdx);
   }
   else
   {
      free(msh);
      return(0);
   }
}