static int MqttClient_WaitType(MqttClient *client, void *packet_obj,
    byte wait_type, word16 wait_packet_id, int timeout_ms)
{
    int rc;
    word16 packet_id;
    MqttPacketType packet_type;
#ifdef WOLFMQTT_MULTITHREAD
    MqttPendResp *pendResp;
    int readLocked;
#endif
    MqttMsgStat* mms_stat;
    int waitMatchFound;
    if (client == NULL || packet_obj == NULL) {
        return MQTT_CODE_ERROR_BAD_ARG;
    }
    mms_stat = (MqttMsgStat*)packet_obj;
wait_again:
    packet_id = 0;
    packet_type = MQTT_PACKET_TYPE_RESERVED;
#ifdef WOLFMQTT_MULTITHREAD
    pendResp = NULL;
    readLocked = 0;
#endif
    waitMatchFound = 0;
#ifdef WOLFMQTT_DEBUG_CLIENT
    PRINTF("MqttClient_WaitType: Type %s (%d), ID %d",
        MqttPacket_TypeDesc((MqttPacketType)wait_type),
            wait_type, wait_packet_id);
#endif
    switch ((int)*mms_stat)
    {
        case MQTT_MSG_BEGIN:
        {
        #ifdef WOLFMQTT_MULTITHREAD
            rc = wm_SemLock(&client->lockRecv);
            if (rc != 0) {
                PRINTF("MqttClient_WaitType: recv lock error!");
                return rc;
            }
            readLocked = 1;
        #endif
            client->packet.stat = MQTT_PK_BEGIN;
        }
        FALL_THROUGH;
    #ifdef WOLFMQTT_V5
        case MQTT_MSG_AUTH:
    #endif
        case MQTT_MSG_WAIT:
        {
        #ifdef WOLFMQTT_MULTITHREAD
            pendResp = NULL;
            rc = wm_SemLock(&client->lockClient);
            if (rc == 0) {
                if (MqttClient_RespList_Find(client, (MqttPacketType)wait_type, 
                    wait_packet_id, &pendResp)) {
                    if (pendResp->packetDone) {
                        rc = pendResp->packet_ret;
                    #ifdef WOLFMQTT_DEBUG_CLIENT
                        PRINTF("PendResp already Done %p: Rc %d", pendResp, rc);
                    #endif
                        MqttClient_RespList_Remove(client, pendResp);
                        wm_SemUnlock(&client->lockClient);
                        wm_SemUnlock(&client->lockRecv);
                        return rc;
                    }
                }
                wm_SemUnlock(&client->lockClient);
            }
            else {
                break; 
            }
        #endif 
            *mms_stat = MQTT_MSG_WAIT;
            rc = MqttPacket_Read(client, client->rx_buf, client->rx_buf_len,
                    timeout_ms);
            if (rc <= 0) {
                break;
            }
            client->packet.buf_len = rc;
            rc = MqttClient_DecodePacket(client, client->rx_buf,
                client->packet.buf_len, NULL, &packet_type, NULL, &packet_id);
            if (rc < 0) {
                break;
            }
        #ifdef WOLFMQTT_DEBUG_CLIENT
            PRINTF("Read Packet: Len %d, Type %d, ID %d",
                client->packet.buf_len, packet_type, packet_id);
        #endif
            *mms_stat = MQTT_MSG_READ;
        }
        FALL_THROUGH;
        case MQTT_MSG_READ:
        case MQTT_MSG_READ_PAYLOAD:
        {
            MqttPacketType use_packet_type;
            void* use_packet_obj;
        #ifdef WOLFMQTT_MULTITHREAD
            readLocked = 1; 
        #endif
            if (*mms_stat == MQTT_MSG_READ_PAYLOAD) {
                packet_type = MQTT_PACKET_TYPE_PUBLISH;
            }
            if ((wait_type == MQTT_PACKET_TYPE_ANY ||
                 wait_type == packet_type ||
                 MqttIsPubRespPacket(packet_type) == MqttIsPubRespPacket(wait_type)) &&
               (wait_packet_id == 0 || wait_packet_id == packet_id))
            {
                use_packet_obj = packet_obj;
                waitMatchFound = 1;
            }
            else {
                use_packet_obj = &client->msg;
            }
            use_packet_type = packet_type;
        #ifdef WOLFMQTT_MULTITHREAD
            pendResp = NULL;
            rc = wm_SemLock(&client->lockClient);
            if (rc == 0) {
                if (MqttClient_RespList_Find(client, packet_type, packet_id,
                                                               &pendResp)) {
                    pendResp->packetProcessing = 1;
                    use_packet_obj = pendResp->packet_obj;
                    use_packet_type = pendResp->packet_type;
                    waitMatchFound = 0;
                }
                wm_SemUnlock(&client->lockClient);
            }
            else {
                break; 
            }
        #endif 
            rc = MqttClient_HandlePacket(client, use_packet_type,
                use_packet_obj, timeout_ms);
        #ifdef WOLFMQTT_NONBLOCK
            if (rc == MQTT_CODE_CONTINUE) {
                return rc;
            }
        #endif
            if (rc >= 0) {
                rc = MQTT_CODE_SUCCESS;
            }
        #ifdef WOLFMQTT_MULTITHREAD
            if (pendResp) {
                if (wm_SemLock(&client->lockClient) == 0) {
                    pendResp->packetDone = 1;
                    pendResp->packet_ret = rc;
                #ifdef WOLFMQTT_DEBUG_CLIENT
                    PRINTF("PendResp Done %p", pendResp);
                #endif
                    pendResp = NULL;
                    wm_SemUnlock(&client->lockClient);
                }
            }
        #endif 
            break;
        }
        case MQTT_MSG_WRITE:
        case MQTT_MSG_WRITE_PAYLOAD:
        default:
        {
        #ifdef WOLFMQTT_DEBUG_CLIENT
            PRINTF("MqttClient_WaitType: Invalid state %d!", *mms_stat);
        #endif
            rc = MQTT_CODE_ERROR_STAT;
            break;
        }
    } 
#ifdef WOLFMQTT_NONBLOCK
    if (rc != MQTT_CODE_CONTINUE)
#endif
    {
        *mms_stat = MQTT_MSG_BEGIN;
    }
#ifdef WOLFMQTT_MULTITHREAD
    if (readLocked) {
        wm_SemUnlock(&client->lockRecv);
    }
#endif
    if (rc < 0) {
    #ifdef WOLFMQTT_DEBUG_CLIENT
        PRINTF("MqttClient_WaitType: Failure: %s (%d)",
            MqttClient_ReturnCodeToString(rc), rc);
    #endif
        return rc;
    }
    if (!waitMatchFound) {
        goto wait_again;
    }
    return rc;
}