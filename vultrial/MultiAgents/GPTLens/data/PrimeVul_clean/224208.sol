void publish(Topic *iterator, size_t start, size_t stop, std::string_view topic, std::pair<std::string_view, std::string_view> message) {
        for (; stop != std::string::npos; start = stop + 1) {
            stop = topic.find('/', start);
            std::string_view segment = topic.substr(start, stop - start);
            if (segment.length() == 1) {
                if (segment[0] == '+' || segment[0] == '#') {
                    return;
                }
            }
            if (iterator->terminatingWildcardChild) {
                iterator->terminatingWildcardChild->messages[messageId] = message;
                if (!iterator->terminatingWildcardChild->triggered) {
                    if (numTriggeredTopics == 64) {
                        drain();
                    }
                    triggeredTopics[numTriggeredTopics++] = iterator->terminatingWildcardChild;
                    iterator->terminatingWildcardChild->triggered = true;
                }
            }
            if (iterator->wildcardChild) {
                publish(iterator->wildcardChild, stop + 1, stop, topic, message);
            }
            std::map<std::string_view, Topic *>::iterator it = iterator->children.find(segment);
            if (it == iterator->children.end()) {
                return;
            }
            iterator = it->second;
        }
        iterator->messages[messageId] = message;
        if (!iterator->triggered) {
            if (numTriggeredTopics == 64) {
                drain();
            }
            triggeredTopics[numTriggeredTopics++] = iterator;
            iterator->triggered = true;
        }
    }