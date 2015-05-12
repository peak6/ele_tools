#!/usr/bin/env python

from setuptools import setup
import PGUtil

setup(name=PGUtil.__name__,
      version=PGUtil.__version__,
      description="PGUtil is a set of helper classes for managing PostgreSQL instances.",
      long_description=PGUtil.__doc__,
      author='Shaun M. Thomas',
      author_email='sthomas@peak6.com',
      license='New BSD License',
      url='http://www.peak6.com/',
      packages=['PGUtil', 'PGUtil.scripts'],
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
              'pgutil_report = PGUtil.scripts.instances:main',
          ]
      }
)
