# COPY versus ADD (slide 145). The build context holds one archive, site.tar.gz.
FROM ubuntu
# COPY puts the archive into the image as it is.
COPY site.tar.gz /copied/
# ADD unpacks a local tar archive into the destination.
ADD site.tar.gz /added/
