#!/usr/bin/env python

from setuptools import setup
import EleTools

setup(name=EleTools.__name__,
      version=EleTools.__version__,
      description="ele_tools is a set of helper classes for managing PostgreSQL instances, mainly for ElepHaaS.",
      long_description=EleTools.__doc__,
      author='Shaun M. Thomas',
      author_email='sthomas@peak6.com',
      license='Apache License 2.0',
      url='http://www.peak6.com/',
      packages=['EleTools', 'EleTools.scripts'],
      tests_require=['nose>=0.11',],
      install_requires=['psycopg2'],
      test_suite = 'nose.collector',
      platforms = 'all',
      classifiers = [
        'Development Status :: 4 - Beta',
        'Environment :: Console',
        'Intended Audience :: Developers',
        'Intended Audience :: System Administrators',
        'License :: OSI Approved :: BSD License',
        'Operating System :: OS Independent',
        'Programming Language :: Python',
        'Topic :: Software Development :: Libraries',
        'Topic :: System :: Systems Administration',
        'Topic :: Utilities',
      ],
      entry_points = {
          'console_scripts': [
              'ele_report = EleTools.scripts.instances:main',
          ]
      }
)
