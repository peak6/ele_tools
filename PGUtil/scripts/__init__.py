from PGUtil import __version__
from argparse import ArgumentParser

import logging
import sys

def get_arg_parser(command_desc):
    """ Get A Commonly Bootstrapped Parser for PostgreSQL CLI Tools

    All PostgreSQL CLI in this library use several common settings. All
    this function does is create a parser, bootstrap those options, and
    return the raw parser object. In this case, we use argparse.

    Options Defined:

    * -c/--config : Config file to read for operation settings.
    * -L/--log    : Full path to output log file.
    * -d/--debug  : Enable verbose debugging output.

    This function returns the raw parser in case the caller wants to define a few
    new options before parsing arguments.

    :param command_desc: Description to display in command help text.

    :retval object: Returns an argparse parser object.
    """

    parser = ArgumentParser(version=__version__,
        description=command_desc,
        conflict_handler="resolve"
    )

    parser.add_argument('-c', '--config', action='store',
        help="Full path to the %(prog)s configuration file. Please see " +
             "documentation for instructions on building this file. " +
             "Default: %(default)s"
    )

    parser.add_argument('-d', '--debug', action='store_true',
        help="Enable debugging output."
    )

    parser.add_argument('-L', '--log', action='store',
        help="Full path to log output. If nothing is specified, logs " +
             "will go to standard output."
    )

    return parser


def handler(type, value, traceback):
    """ Exception Wrapper for CLI Scripts
    
    The CLI tools log exceptions where necessary. Uncaught exceptions were
    probably re-raised for convenience or development. Setting this handler
    to sys.excepthook will suppress all uncaught exceptions with a note to
    check the log output.
    """

    logging.error(value)
    print "Requested operation has failed. Please check script log."
    print "Last message: %s" % value
    sys.exit(1)


def init_logging(log_path=None, debug_output=False):
    """ Set up the Python Logging System

    Our scripts will log either to STDOUT or a specified file, with either
    extended debugging, or just Info output. With no options, prints
    information statements to standard output.

    :param log_path: Full path to log file, or None for STDOUT.
    :param debug_output: Enable debugging statements. Info only otherwise.
    """

    log_level = debug_output and logging.DEBUG or logging.INFO

    if log_path:
        logging.basicConfig(
            filename=log_path, level=log_level,
            format="%(asctime)s %(levelname)s: %(message)s",
            datefmt='%Y-%m-%d %I:%M:%S'
        )
    else:
        logging.basicConfig(
            stream=sys.stdout, level=log_level,
            format="%(asctime)s %(levelname)s: %(message)s",
            datefmt='%Y-%m-%d %I:%M:%S'
        )
