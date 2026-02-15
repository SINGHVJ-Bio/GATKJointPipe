from setuptools import setup, find_packages

setup(
    name='GATKJointPipe',
    version='1.0.0',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'pyyaml>=5.1',
    ],
    entry_points={
        'console_scripts': [
            'jointcalling = pipeline.cli:main',
        ],
    },
    package_data={
        '': ['scripts/*.sh'],
    },
    author='Vijay Singh',
    description='A config‑driven pipeline for GATK joint calling and post‑processing',
    license='MIT',
)