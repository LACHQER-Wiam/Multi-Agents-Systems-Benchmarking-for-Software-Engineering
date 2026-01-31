[
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Potential buffer overflow",
        "reason": "The use of strncpy can lead to buffer overflow if pipePath exceeds the size of local.sun_path. This could overwrite adjacent memory and potentially allow an attacker to execute arbitrary code.",
        "file_name": "400103.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "TOCTOU race condition",
        "reason": "There is a time-of-check-to-time-of-use (TOCTOU) race condition between the unlink and bind calls. An attacker could exploit this by creating a symbolic link or other malicious file at local.sun_path between the two calls, leading to a potential privilege escalation or unauthorized access.",
        "file_name": "400103.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Insecure file permissions",
        "reason": "The chmod call only sets permissions for the owner, but if an attacker can control the ownership or if the server runs with elevated privileges, it may not prevent unauthorized access by other users. The directory permissions and ownership should be validated to avoid unauthorized access.",
        "file_name": "400103.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Potential buffer overflow",
        "reason": "The use of strncpy can lead to buffer overflow if pipePath.c_str() is longer than sizeof(local.sun_path). strncpy does not null-terminate if the source string is too long, leading to potential buffer overflow.",
        "file_name": "400103.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "TOCTOU race condition",
        "reason": "The code is vulnerable to time-of-check-to-time-of-use (TOCTOU) race conditions. After the call to unlink and before bind, another process could create a symbolic link or a file at the same path, leading to potential security breaches.",
        "file_name": "400103.sol"
    },
    {
        "function_name": "PipeSocketHandler::listen",
        "code": "set<int> PipeSocketHandler::listen(const SocketEndpoint& endpoint) {\n  lock_guard<std::recursive_mutex> guard(globalMutex);\n  string pipePath = endpoint.name();\n  if (pipeServerSockets.find(pipePath) != pipeServerSockets.end()) {\n    throw runtime_error(\"Tried to listen twice on the same path\");\n  }\n  sockaddr_un local;\n  int fd = socket(AF_UNIX, SOCK_STREAM, 0);\n  FATAL_FAIL(fd);\n  initServerSocket(fd);\n  local.sun_family = AF_UNIX; \n  strncpy(local.sun_path, pipePath.c_str(), sizeof(local.sun_path));\n  unlink(local.sun_path);\n  FATAL_FAIL(::bind(fd, (struct sockaddr*)&local, sizeof(sockaddr_un)));\n  ::listen(fd, 5);\n#ifndef WIN32\n  FATAL_FAIL(::chmod(local.sun_path, S_IRUSR | S_IWUSR | S_IXUSR));\n#endif\n  pipeServerSockets[pipePath] = set<int>({fd});\n  return pipeServerSockets[pipePath];\n}",
        "vulnerability": "Insecure file permissions",
        "reason": "The chmod call sets permissions that include execute permission (S_IXUSR), which is generally not necessary for UNIX domain sockets and could be exploited by an attacker to execute code or access sensitive data.",
        "file_name": "400103.sol"
    }
]