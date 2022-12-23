To update gnb conf files from
https://gitlab.eurecom.fr/oai/openairinterface5g/-/tree/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF

First retrieve the gnb.conf than update the gnb docker image to use -- latest develop version for both gnb image and conf file...

Example:
wget https://gitlab.eurecom.fr/oai/openairinterface5g/-/raw/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.2x2.usrpn300.conf?inline=false
mv wget https://gitlab.eurecom.fr/oai/openairinterface5g/-/raw/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.2x2.usrpn300.conf?inline=false wget https://gitlab.eurecom.fr/oai/openairinterface5g/-/raw/develop/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.2x2.usrpn300.conf

After that, apply some any possible constant changes required for R2lab environment:
 - NSSAI sd info to be added
 - sdr_addrs to be added
TBD: to be added automatically in our scripts according to RRU model used. 

Then create the new oai-gnb(-s\aw2s) docker images on a fit node and upload the image on dockerhub
