trackhub-registry
=================

This repository contains the specification and implementation of the TrackHub registry.

TrackHub is a technology that allows efficient integration of large-scale genomic data sets into modern genome browsers. TrackHubs represent a way to collate related data sets through a single attachable URL (Uniform Resource Locator) for presentation as a single entity. These data sets are provided in the binary indexed file formats (e.g. bigBed, bigWig, BAM, VCF) supporting partial downloads and caching, significantly improving performance over DAS. They can be hosted on a
simple HTTP or FTP server reducing the cost of setup and maintenance.

Both UCSC and Ensembl have developed initial support for this technology, but there are still limitations for many users, and Ensembl's support remains incomplete. At present integration of TrackHubs into the Ensembl and UCSC genome browsers involves the copy-paste of a known URL. Discovery is based on word of mouth or the provision of manually curated portal pages hosted by the genome browsers or projects (http://genome.ucsc.edu/cgi-bin/hgHubConnect).

The aim here is to develop a registry system, similar in goals to the DAS registry (http://www.dasregistry.org), for third parties to advertise TrackHubs, and to make it easier for researchers around the world to discover and use TrackHubs containing different types of genomic research data.

[![Build Status](https://travis-ci.org/Ensembl/trackhub-registry.svg?branch=master)](https://travis-ci.org/Ensembl/trackhub-registry)
