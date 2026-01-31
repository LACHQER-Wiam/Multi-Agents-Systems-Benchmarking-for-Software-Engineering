void Image::printIFDStructure(BasicIo& io, std::ostream& out, Exiv2::PrintStructureOption option,uint32_t start,bool bSwap,char c,int depth)
    {
        depth++;
        bool bFirst  = true  ;
        const size_t dirSize = 32;
        DataBuf  dir(dirSize);
        bool bPrint = option == kpsBasic || option == kpsRecursive;
        do {
            io.seek(start,BasicIo::beg);
            io.read(dir.pData_, 2);
            uint16_t   dirLength = byteSwap2(dir,0,bSwap);
            bool tooBig = dirLength > 500;
            if ( tooBig ) throw Error(55);
            if ( bFirst && bPrint ) {
                out << Internal::indent(depth) << Internal::stringFormat("STRUCTURE OF TIFF FILE (%c%c): ",c,c) << io.path() << std::endl;
                if ( tooBig ) out << Internal::indent(depth) << "dirLength = " << dirLength << std::endl;
            }
            for ( int i = 0 ; i < dirLength ; i ++ ) {
                if ( bFirst && bPrint ) {
                    out << Internal::indent(depth)
                        << " address |    tag                              |     "
                        << " type |    count |    offset | value\n";
                }
                bFirst = false;
                io.read(dir.pData_, 12);
                uint16_t tag    = byteSwap2(dir,0,bSwap);
                uint16_t type   = byteSwap2(dir,2,bSwap);
                uint32_t count  = byteSwap4(dir,4,bSwap);
                uint32_t offset = byteSwap4(dir,8,bSwap);
                if ( !typeValid(type) ) {
                    std::cerr << "invalid type value detected in Image::printIFDStructure:  " << type << std::endl;
                    start = 0; 
                    throw Error(56);
                    break; 
                }
                std::string sp  = "" ; 
                uint32_t kount  = isPrintXMP(tag,option) ? count 
                                : isPrintICC(tag,option) ? count 
                                : isStringType(type)     ? (count > 32 ? 32 : count) 
                                : count > 5              ? 5
                                : count
                                ;
                uint32_t pad    = isStringType(type) ? 1 : 0;
                uint32_t size   = isStringType(type) ? 1
                                : is2ByteType(type)  ? 2
                                : is4ByteType(type)  ? 4
                                : is8ByteType(type)  ? 8
                                : 1
                                ;
                DataBuf  buf(size*count + pad+20);  
                std::memcpy(buf.pData_,dir.pData_+8,4);  
                const bool bOffsetIsPointer = count*size > 4;
                if ( bOffsetIsPointer ) {         
                    size_t   restore = io.tell();  
                    io.seek(offset,BasicIo::beg);  
                    io.read(buf.pData_,count*size);
                    io.seek(restore,BasicIo::beg); 
                }
                if ( bPrint ) {
                    const uint32_t address = start + 2 + i*12 ;
                    const std::string offsetString = bOffsetIsPointer?
                        Internal::stringFormat("%10u", offset):
                        "";
                    out << Internal::indent(depth)
                    << Internal::stringFormat("%8u | %#06x %-28s |%10s |%9u |%10s | "
                                              ,address,tag,tagName(tag).c_str(),typeName(type),count,offsetString.c_str());
                    if ( isShortType(type) ){
                        for ( size_t k = 0 ; k < kount ; k++ ) {
                            out << sp << byteSwap2(buf,k*size,bSwap);
                            sp = " ";
                        }
                    } else if ( isLongType(type) ){
                        for ( size_t k = 0 ; k < kount ; k++ ) {
                            out << sp << byteSwap4(buf,k*size,bSwap);
                            sp = " ";
                        }
                    } else if ( isRationalType(type) ){
                        for ( size_t k = 0 ; k < kount ; k++ ) {
                            uint32_t a = byteSwap4(buf,k*size+0,bSwap);
                            uint32_t b = byteSwap4(buf,k*size+4,bSwap);
                            out << sp << a << "/" << b;
                            sp = " ";
                        }
                    } else if ( isStringType(type) ) {
                        out << sp << Internal::binaryToString(buf, kount);
                    }
                    sp = kount == count ? "" : " ...";
                    out << sp << std::endl;
                    if ( option == kpsRecursive && (tag == 0x8769  || tag == 0x014a  || type == tiffIfd) ) {
                        for ( size_t k = 0 ; k < count ; k++ ) {
                            size_t   restore = io.tell();
                            uint32_t offset = byteSwap4(buf,k*size,bSwap);
                            printIFDStructure(io,out,option,offset,bSwap,c,depth);
                            io.seek(restore,BasicIo::beg);
                        }
                    } else if ( option == kpsRecursive && tag == 0x83bb  ) {
                        size_t   restore = io.tell();  
                        io.seek(offset,BasicIo::beg);  
                        byte* bytes=new byte[count] ;  
                        io.read(bytes,count)        ;  
                        io.seek(restore,BasicIo::beg); 
                        IptcData::printStructure(out,bytes,count,depth);
                        delete[] bytes;                
                    }  else if ( option == kpsRecursive && tag == 0x927c  && count > 10) {
                        size_t   restore = io.tell();  
                        uint32_t jump= 10           ;
                        byte     bytes[20]          ;
                        const char* chars = (const char*) &bytes[0] ;
                        io.seek(offset,BasicIo::beg);  
                        io.read(bytes,jump    )     ;  
                        bytes[jump]=0               ;
                        if ( ::strcmp("Nikon",chars) == 0 ) {
                            byte* bytes=new byte[count-jump] ;  
                            io.read(bytes,count-jump)        ;  
                            MemIo memIo(bytes,count-jump)    ;  
                            printTiffStructure(memIo,out,option,depth);
                            delete[] bytes                   ;  
                        } else {
                            io.seek(0,BasicIo::beg);  
                            printIFDStructure(io,out,option,offset,bSwap,c,depth);
                        }
                        io.seek(restore,BasicIo::beg); 
                    }
                }
                if ( isPrintXMP(tag,option) ) {
                    buf.pData_[count]=0;
                    out << (char*) buf.pData_;
                }
                if ( isPrintICC(tag,option) ) {
                    out.write((const char*)buf.pData_,count);
                }
            }
            if ( start ) {
                io.read(dir.pData_, 4);
                start = tooBig ? 0 : byteSwap4(dir,0,bSwap);
            }
        } while (start) ;
        if ( bPrint ) {
            out << Internal::indent(depth) << "END " << io.path() << std::endl;
        }
        out.flush();
        depth--;
    }