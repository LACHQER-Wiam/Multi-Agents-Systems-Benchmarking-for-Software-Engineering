[
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Buffer overflow",
        "reason": "The use of strcpy to copy the pipe path into local.sun_path can lead to a buffer overflow if the length of the pipe path exceeds the allocated size of local.sun_path. This vulnerability can be exploited by an attacker to execute arbitrary code or crash the application.",
        "file_name": "207703.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Time-of-check to time-of-use (TOCTOU) race condition",
        "reason": "The use of unlink followed by bind creates a window where a TOCTOU race condition can occur. An attacker could exploit this by creating a symbolic link between the unlink and bind calls, potentially redirecting the server to bind to an unintended file path, leading to unauthorized access or denial of service.",
        "file_name": "207703.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Insecure file permissions",
        "reason": "The chmod call sets the permissions to allow read, write, and execute by the owner but doesn't restrict access from others. If the application is running with elevated privileges, an attacker could potentially exploit this to gain unauthorized access or escalate privileges by interacting with the socket file.",
        "file_name": "207703.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The use of strcpy can lead to a buffer overflow if the length of pipePath exceeds the size of local.sun_path. This is a potential security risk since it can cause memory corruption and could be exploited to execute arbitrary code.",
        "file_name": "207703.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Race Condition",
        "reason": "The use of unlink before bind can lead to a race condition vulnerability. An attacker could replace the file at local.sun_path between the unlink and bind calls, potentially leading to unauthorized access or privilege escalation.",
        "file_name": "207703.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strcpy(local.sun_path, pipePath.c_str());\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Insecure File Permissions",
        "reason": "Setting the permissions to S_IRUSR | S_IWUSR | S_IXUSR (0700), while commonly used, can still be insecure if the file system is mounted with certain options that allow other users to interact with the socket file. A more secure approach would ensure the socket is only accessible to the intended user and process.",
        "file_name": "207703.sol"
    }
]