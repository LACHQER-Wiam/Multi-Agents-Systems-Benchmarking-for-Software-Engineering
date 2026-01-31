[
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Memory Leak",
        "reason": "The code allocates memory for 'result' and 'copy' variables using 'malloc' and 'realloc' functions but fails to free the memory allocated for 'result' in case of an error. This can lead to a memory leak where the allocated memory is not properly released, causing the program to consume excessive memory and potentially crash.",
        "file_name": "351182.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Buffer Overflow",
        "reason": "The code does not perform proper bounds checking when allocating memory for 'result' and 'copy' variables. An attacker could provide a 'delim' input that results in a large number of tokens being generated, leading to a buffer overflow when allocating memory for 'result'. This can be exploited to overwrite adjacent memory and potentially execute malicious code.",
        "file_name": "351182.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Null Pointer Dereference",
        "reason": "The code does not check if the 'copy' variable returned by 'dupstr' function is NULL before using it in the 'strtok' function. If 'dupstr' fails to allocate memory and returns NULL, passing it to 'strtok' would result in a null pointer dereference, leading to a crash or potential denial of service.",
        "file_name": "351182.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Memory leak",
        "reason": "The split function allocates memory for 'result' using realloc but does not free this memory if an error condition is encountered. This can lead to memory leaks if the function returns NULL prematurely without freeing the allocated memory.",
        "file_name": "351182.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "Double free",
        "reason": "The split function frees the 'result' array twice in the error handling code if memory allocation fails. This can lead to a double free vulnerability, where an attacker could potentially exploit this to cause a denial of service or execute arbitrary code.",
        "file_name": "351182.sol"
    },
    {
        "function_name": "split",
        "code": "static char ** split(const char *arg, const char *delim) {\n  char *copy = dupstr(arg);\n  char **result = NULL;\n  int i = 0;\n  for (char *cptr = strtok(copy, delim); cptr; cptr = strtok(NULL, delim)) {\n    char **tmp = realloc (result, sizeof *result * (i + 1));\n    if (!tmp && result) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      free(copy);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = dupstr(cptr);\n  }\n  free(copy);\n  if (i) {\n    char **tmp = realloc(result, sizeof *result * (i + 1));\n    if (!tmp) {\n      while (i > 0) {\n\tfree(result[--i]);\n      }\n      free(result);\n      return NULL;\n    }\n    result = tmp;\n    result[i++] = NULL;\n  }\n  return result;\n}",
        "vulnerability": "NULL pointer dereference",
        "reason": "If the 'result' array is not properly allocated due to a memory allocation failure, the function may return NULL. Subsequent code that attempts to access 'result' or its elements without proper error handling can result in a NULL pointer dereference vulnerability, potentially leading to a crash or undefined behavior.",
        "file_name": "351182.sol"
    }
]