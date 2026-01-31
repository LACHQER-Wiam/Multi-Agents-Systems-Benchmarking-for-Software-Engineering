[
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Memory Leak",
        "reason": "The code dynamically allocates memory for the 'result' variable using 'realloc', but when 'tmp' is NULL, the previous memory allocated for 'result' is not freed before returning NULL. This leads to a memory leak as the allocated memory is not properly released.",
        "file_name": "204073.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Double Free",
        "reason": "The code contains multiple points where 'free' is called on 'result' without setting it to NULL afterwards. This can lead to a double free vulnerability, where the memory pointed to by 'result' is freed more than once, potentially causing memory corruption and crashes.",
        "file_name": "204073.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not perform proper bounds checking when allocating memory for the 'result' array. If the input string 'arg' is too large or contains a large number of tokens separated by 'delim', it can lead to a buffer overflow when writing to 'result'. This can be exploited by an attacker to overwrite adjacent memory and potentially execute arbitrary code.",
        "file_name": "204073.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Memory Leak",
        "reason": "The code allocates memory for 'result' using realloc but fails to free the memory if realloc fails. This can lead to memory leaks where the allocated memory is not properly released, causing the program to consume more memory than necessary. An attacker could potentially exploit this vulnerability by repeatedly calling the split function with malicious input, causing the program to run out of memory and crash.",
        "file_name": "204073.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Null Pointer Dereference",
        "reason": "If realloc fails to allocate memory and returns NULL, the code does not handle this case properly. It continues to access 'result' assuming it is a valid pointer, which can result in a null pointer dereference. An attacker could exploit this vulnerability by providing input that triggers the failure of realloc, leading to a crash or potentially allowing for arbitrary code execution.",
        "file_name": "204073.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Uninitialized Memory Read",
        "reason": "The function uses strtok to tokenize the input string 'arg'. If the input string 'arg' is modified or corrupted in some way before calling the split function, strtok may read uninitialized memory or read beyond the bounds of 'arg'. An attacker could exploit this vulnerability by manipulating the input string to expose sensitive information or potentially crash the program.",
        "file_name": "204073.sol"
    }
]