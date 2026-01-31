[
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "setuid failure handling",
        "reason": "The code attempts to set the UID of the process to a non-privileged user using setuid. If setuid fails due to an error other than EAGAIN (e.g., EPERM), the process continues execution with elevated privileges. This failure to properly handle all setuid errors can lead to the process inadvertently retaining root privileges, making it susceptible to privilege escalation attacks.",
        "file_name": "212152.sol"
    },
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "incorrect privilege tracking",
        "reason": "The function updates the effective user ID (euid) and group ID (egid) in the current_user structure without verifying the success of setuid and setgid calls. This can lead to a false sense of security where the program believes it is running with reduced privileges, but it might still have elevated privileges if the setuid or setgid calls failed. This discrepancy can be exploited by attackers to perform unauthorized actions.",
        "file_name": "212152.sol"
    },
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "inadequate setgid error handling",
        "reason": "The setgid call is not adequately handled when it fails. Unlike the setuid failure handling, there is no conditional exit or alternative logic to handle setgid failures. This oversight allows the process to possibly continue executing with unintended group privileges, which can be exploited for unauthorized access or actions, particularly in scenarios where group-based access control is used.",
        "file_name": "212152.sol"
    },
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "inconsistent error handling on setuid failure",
        "reason": "The function attempts to change the effective user ID using setuid. If this fails, it logs an error with sys_error but only exits under certain conditions (EAGAIN and EXIT_ON_SETUID_FAILURE defined). This inconsistency can lead to a situation where the function may continue execution with elevated privileges, potentially allowing an attacker to exploit these privileges.",
        "file_name": "212152.sol"
    },
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "lack of error handling on setgid failure",
        "reason": "The call to setgid may fail, but the code only logs an error and does not handle the failure by terminating or taking corrective action. This could allow the function to continue execution with an incorrect group ID, potentially leading to privilege escalation or unauthorized access.",
        "file_name": "212152.sol"
    },
    {
        "function_name": "disable_priv_mode",
        "code": "disable_priv_mode ()\n{\n  int e;\n  if (setuid (current_user.uid) < 0)\n    {\n      e = errno;\n      sys_error (_(\"cannot set uid to %d: effective uid %d\"), current_user.uid, current_user.euid);\n#if defined (EXIT_ON_SETUID_FAILURE)\n      if (e == EAGAIN)\n\texit (e);\n#endif\n    }\n  if (setgid (current_user.gid) < 0)\n    sys_error (_(\"cannot set gid to %d: effective gid %d\"), current_user.gid, current_user.egid);\n  current_user.euid = current_user.uid;\n  current_user.egid = current_user.gid;\n}",
        "vulnerability": "insecure privilege state assumptions",
        "reason": "The function sets the effective user and group IDs in the current_user structure after attempting to call setuid and setgid. However, if these calls fail, the structure may not accurately reflect the actual privilege state of the process. This discrepancy can be exploited by an attacker to bypass security checks that rely on the integrity of these fields.",
        "file_name": "212152.sol"
    }
]