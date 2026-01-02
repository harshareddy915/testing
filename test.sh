# Use a minimal operating system base image, such as Alpine Linux, instead of a Python-specific image.
FROM alpine:3.18

# Set environment variables to control Python's behavior and installation paths.
ENV PYTHON_VERSION=3.11.8
ENV PYTHON_ROOT=/opt/python
ENV PATH="$PYTHON_ROOT/bin:$PATH"

# Define the build and runtime dependencies needed for compiling Python and running pip.
RUN apk add --no-cache \
    # Build dependencies: tools required to download and compile the Python source code.
    build-base linux-headers openssl-dev bzip2-dev zlib-dev readline-dev sqlite-dev \
    # Runtime dependencies: libraries Python needs to function (many are also used for building).
    libffi-dev openssl bzip2 zlib readline sqlite-libs && \
    \
    # Create the directory where Python will be installed.
    mkdir -p /tmp/python_src && \
    cd /tmp/python_src && \
    \
    # Download the Python source code from the official website.
    # The 'wget' command needs to be added as a temporary build dependency if not included in build-base.
    apk add --no-cache wget && \
    wget www.python.org && \
    tar -xvf Python-$PYTHON_VERSION.tar.xz && \
    cd Python-$PYTHON_VERSION && \
    \
    # Configure and compile Python.
    ./configure --prefix=$PYTHON_ROOT --enable-optimizations --with-openssl && \
    make -j$(nproc) && \
    make install && \
    \
    # Install pip by running the "ensurepip" module which is part of the standard library.
    # It ensures pip is installed and creates symlinks for pip and pip3 scripts.
    python3 -m ensurepip --upgrade && \
    \
    # Clean up temporary build files and source code to reduce final image size.
    rm -rf /tmp/python_src && \
    # Remove build dependencies that are no longer needed after compilation.
    apk del build-base linux-headers openssl-dev bzip2-dev zlib-dev readline-dev sqlite-dev wget && \
    # Clean up the apk cache
    rm -rf /var/cache/apk/*

# Verify the installations
CMD ["python3", "--version"]
