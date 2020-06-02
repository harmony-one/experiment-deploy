import subprocess
import os
import sys
import logging

from pyhmy.util import (
    Typgpy
)

ipv4_regex = r"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"


def setup_logger(log_file, logger_name, do_print=True, verbose=True):
    """
    Setup the logger for the snapshot package and returns the logger.
    """
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    logger = logging.getLogger(logger_name)
    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(
        logging.Formatter(f"(%(threadName)s)[%(asctime)s] %(message)s"))
    logger.addHandler(file_handler)
    if do_print:
        logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    logger.debug("===== NEW LOG =====")
    if verbose:
        print(f"Logs saved to: {log_file}")
    return logger


def interact(prompt, selection_list, sort=True):
    """
    Prompt the user with `prompt` and an enumerated selection from a possibly sorted `selection_list`.
    Take in an integer, n, such that 0 <= n < len(`selection_list`).
    If a `log` is provided, log the interaction and all errors at the info and error level respectively.

    Keeps prompting user for input if input is invalid.
    Prints user interaction before returning.

    Note that all new lines from `prompt` and `selection_list` will be removed.

    Returns n and corresponding selection string from `selection_list`.
    """
    if not selection_list:
        return
    input_prompt = f"{Typgpy.BOLD}Select option (number):{Typgpy.ENDC}\n> "

    prompt, selection_list = prompt.replace("\n", ""), [e.replace("\n", "") for e in selection_list]
    if sort:
        selection_list = sorted(selection_list, reverse=True)
    prompt_new_line_count = sum(1 for el in selection_list if el) + 3  # 1 for given prompt, 2 for input prompt
    if prompt:
        prompt_new_line_count += 1
    printed_new_line_count = 0
    print()

    while True:
        if prompt:
            print(prompt)
        for i, selection in enumerate(selection_list):
            print(f"{Typgpy.BOLD}[{i}]{Typgpy.ENDC}\t{selection}")
        user_input = input(input_prompt)
        printed_new_line_count += prompt_new_line_count
        try:
            n = int(user_input)
            if n >= len(selection_list):
                continue
            selection_report = f"{prompt} {Typgpy.BOLD}[{n}]{Typgpy.ENDC} {selection_list[n]}".strip()
            for i in range(printed_new_line_count):
                sys.stdout.write("\033[K")
                if i + 1 < printed_new_line_count:
                    sys.stdout.write("\033[F")
            print(selection_report)
            return selection_list[n]
        except ValueError:
            pass


def aws_s3_ls(path):
    """
    AWS command to list contents of an s3 bucket anonymously.
    Assumes AWS CLI is setup on machine.

    Raises subprocess.CalledProcessError if aws command fails.
    """
    cmd = ['aws', 's3', 'ls', path]
    return [n.replace('PRE', '').replace("/", "").strip() for n in
            subprocess.check_output(cmd, env=os.environ, timeout=60).decode().split("\n") if "PRE" in n]
