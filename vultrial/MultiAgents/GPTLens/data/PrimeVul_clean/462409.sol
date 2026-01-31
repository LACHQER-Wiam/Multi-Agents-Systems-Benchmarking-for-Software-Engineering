processDataRcvd(ptcpsess_t *const __restrict__ pThis,
	char **buff,
	const int buffLen,
	struct syslogTime *stTime,
	const time_t ttGenTime,
	multi_submit_t *pMultiSub,
	unsigned *const __restrict__ pnMsgs)
{
	DEFiRet;
	char c = **buff;
	int octatesToCopy, octatesToDiscard;
	if(pThis->inputState == eAtStrtFram) {
		if(pThis->bSuppOctetFram && isdigit((int) c)) {
			pThis->inputState = eInOctetCnt;
			pThis->iOctetsRemain = 0;
			pThis->eFraming = TCP_FRAMING_OCTET_COUNTING;
		} else if(pThis->bSPFramingFix && c == ' ') {
			 FINALIZE;
		} else {
			pThis->inputState = eInMsg;
			pThis->eFraming = TCP_FRAMING_OCTET_STUFFING;
		}
	}
	if(pThis->inputState == eInOctetCnt) {
		if(isdigit(c)) {
			if(pThis->iOctetsRemain <= 200000000) {
				pThis->iOctetsRemain = pThis->iOctetsRemain * 10 + c - '0';
			} else {
				errmsg.LogError(0, NO_ERRCODE, "Framing Error in received TCP message: "
						"frame too large (at least %d%c), change to octet stuffing",
						pThis->iOctetsRemain, c);
				pThis->eFraming = TCP_FRAMING_OCTET_STUFFING;
				pThis->inputState = eInMsg;
			}
			*(pThis->pMsg + pThis->iMsg++) = c;
		} else { 
			DBGPRINTF("TCP Message with octet-counter, size %d.\n", pThis->iOctetsRemain);
			if(c != ' ') {
				errmsg.LogError(0, NO_ERRCODE, "Framing Error in received TCP message: "
					    "delimiter is not SP but has ASCII value %d.", c);
			}
			if(pThis->iOctetsRemain < 1) {
				errmsg.LogError(0, NO_ERRCODE, "Framing Error in received TCP message: "
					    "invalid octet count %d.", pThis->iOctetsRemain);
				pThis->eFraming = TCP_FRAMING_OCTET_STUFFING;
			} else if(pThis->iOctetsRemain > iMaxLine) {
				DBGPRINTF("truncating message with %d octets - max msg size is %d\n",
					  pThis->iOctetsRemain, iMaxLine);
				errmsg.LogError(0, NO_ERRCODE, "received oversize message: size is %d bytes, "
					        "max msg size is %d, truncating...", pThis->iOctetsRemain, iMaxLine);
			}
			pThis->inputState = eInMsg;
			pThis->iMsg = 0;
		}
	} else {
		assert(pThis->inputState == eInMsg);
		if (pThis->eFraming == TCP_FRAMING_OCTET_STUFFING) {
			if(pThis->iMsg >= iMaxLine) {
				int i = 1;
				char currBuffChar;
				while(i < buffLen && ((currBuffChar = (*buff)[i]) != '\n'
					&& (pThis->pLstn->pSrv->iAddtlFrameDelim == TCPSRV_NO_ADDTL_DELIMITER
						|| currBuffChar != pThis->pLstn->pSrv->iAddtlFrameDelim))) {
					i++;
				}
				LogError(0, NO_ERRCODE, "error: message received is at least %d byte larger than max msg"
					" size; message will be split starting at: \"%.*s\"\n", i, (i < 32) ? i : 32, *buff);
				doSubmitMsg(pThis, stTime, ttGenTime, pMultiSub);
				++(*pnMsgs);
			}
			if ((c == '\n')
				   || ((pThis->pLstn->pSrv->iAddtlFrameDelim != TCPSRV_NO_ADDTL_DELIMITER)
					   && (c == pThis->pLstn->pSrv->iAddtlFrameDelim))
				   ) { 
				doSubmitMsg(pThis, stTime, ttGenTime, pMultiSub);
				++(*pnMsgs);
				pThis->inputState = eAtStrtFram;
			} else {
				if(pThis->iMsg < iMaxLine) {
					*(pThis->pMsg + pThis->iMsg++) = c;
				}
			}
		} else {
			assert(pThis->eFraming == TCP_FRAMING_OCTET_COUNTING);
			octatesToCopy = pThis->iOctetsRemain;
			octatesToDiscard = 0;
			if (buffLen < octatesToCopy) {
				octatesToCopy = buffLen;
			}
			if (octatesToCopy + pThis->iMsg > iMaxLine) {
				octatesToDiscard = octatesToCopy - (iMaxLine - pThis->iMsg);
				octatesToCopy = iMaxLine - pThis->iMsg;
			}
			memcpy(pThis->pMsg + pThis->iMsg, *buff, octatesToCopy);
			pThis->iMsg += octatesToCopy;
			pThis->iOctetsRemain -= (octatesToCopy + octatesToDiscard);
			*buff += (octatesToCopy + octatesToDiscard - 1);
			if (pThis->iOctetsRemain == 0) {
				doSubmitMsg(pThis, stTime, ttGenTime, pMultiSub);
				++(*pnMsgs);
				pThis->inputState = eAtStrtFram;
			}
		}
	}
finalize_it:
	RETiRet;
}