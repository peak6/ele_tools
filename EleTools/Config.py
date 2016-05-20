#!/usr/bin/env python

from ConfigParser import SafeConfigParser
import os
import re

class Config:
    """ Config class for EleTools CLI Utilities

    This class essentially parses the passed configuration file into section
    and option values. For every section within the config file, all options
    in that section are turned into object attributes. So for example, a file
    with this content:

    [Local]
    db_host
    db_port

    Would be turned into these values:

    * config.local.db_host
    * config.local.db_port

    It also defines dictionary methods so the attributes are convenient
    in text substitution. The same config file would allow this usage:

    print "Host: %(db_host)" % config.local
    """

    config_file = None
    pattern = {}

    class Container:
        """ Basic raw container for section config elements.
        
        This class only exists so we can nest config items under their
        respective sections. With this in place, we can get config groups
        and use all of the config values as object attributes.
        """

        def __getitem__(self, key):
            """ Get an Object Attribute Value

            Config settings are made into object attributes, but in some
            instances, such as string substitutions, it's more convenient to
            use options as a dictionary. This allows that usage.
            """

            if self.__dict__.has_key(key):
                return self.__dict__[key]

            return None


    def __init__(self, config_file, pattern):
        """ Checks for, and Reads a Specified Config File

        In order for CLI operations to remain consistent across all operations,
        a single format is recognized by the library. This file should follow
        recognized sections and options for the CLI library.
        Extra options will be ignored.

        :param config_file: Full path to desired config file.
        :param pattern: Dictionary of sections and fields to search for in
            indicated config file.
        """

        if not os.path.isfile(config_file):
            raise os.error("Config %s does not exist!" % config_file)

        self.config_file = config_file
        self.pattern = pattern
        self.__read_config()


    def __read_config(self):
        """ Read the object config file to control behavior

        This method will read the required configuration file which will set
        several options that control how the backup system operates. Many
        defaults are set based on our current SOP on database instance
        locations and setup.
        """

        conf_parse = SafeConfigParser()

        # Set all of our default parser options to honor the expected
        # behavior. This is not an exhaustive list of config entries.
        # Some are not listed as having no default.

        for section, options in self.pattern.iteritems():
            conf_parse.add_section(section)
            for option, value in options.iteritems():
                conf_parse.set(section, option, value)

        conf_parse.read(self.config_file)

        # Now that we've read the file, grab all items and turn them into
        # object attributes, prefixed with the containing section. This
        # makes it much easier to address each item.

        for k, v in self.pattern.items():
            sect = k.lower()
            cont = self.Container()

            for option in v:
                cont.__dict__[option] = conf_parse.get(k, option)

            self.__dict__[sect] = cont


# Set up the object and external callables.

__all__ = ['Config']
