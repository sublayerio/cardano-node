FROM ubuntu

ENV TZ=Europe/Amsterdam
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# First, update packages and install Ubuntu dependencies.
RUN apt-get update -y
RUN apt-get upgrade -y
RUN apt-get install git \
    jq \
    bc \
    make \
    automake \
    rsync \
    htop \
    curl \
    build-essential \
    pkg-config \
    libffi-dev \
    libgmp-dev \
    libssl-dev \
    libtinfo-dev \
    libsystemd-dev \
    zlib1g-dev \
    make \
    g++ \
    wget \
    libncursesw5 \
    libtool \
    autoconf -y

# Create tmp dir
RUN mkdir $HOME/tmp
WORKDIR /root/tmp

# Install Libsodium.
RUN git clone https://github.com/input-output-hk/libsodium
WORKDIR /root/tmp/libsodium
RUN git checkout 66f017f1
RUN ./autogen.sh
RUN ./configure
RUN make
RUN make install

# Install Cabal.
WORKDIR /root/tmp
RUN wget https://downloads.haskell.org/~cabal/cabal-install-3.2.0.0/cabal-install-3.2.0.0-x86_64-unknown-linux.tar.xz
RUN tar -xf cabal-install-3.2.0.0-x86_64-unknown-linux.tar.xz
RUN rm cabal-install-3.2.0.0-x86_64-unknown-linux.tar.xz cabal.sig
RUN mkdir -p $HOME/.local/bin
RUN mv cabal $HOME/.local/bin/

# Install GHC.
RUN wget https://downloads.haskell.org/ghc/8.10.2/ghc-8.10.2-x86_64-deb9-linux.tar.xz
RUN tar -xf ghc-8.10.2-x86_64-deb9-linux.tar.xz
RUN rm ghc-8.10.2-x86_64-deb9-linux.tar.xz
RUN cd ghc-8.10.2 && ./configure && make install

# Update PATH to include Cabal and GHC and add exports. Your node's location will be in $NODE_HOME. 
ENV HOME=/root
ENV PATH="/root/.local/bin:$PATH"
ENV NODE_HOME=$HOME/cardano-my-node
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

# Update cabal and verify the correct versions were installed successfully.
RUN cabal update
RUN cabal -V
RUN ghc -V

# Build the node from source
# Download source code and switch to the latest tag.
WORKDIR /tmp
RUN git clone https://github.com/input-output-hk/cardano-node.git
WORKDIR /tmp/cardano-node
RUN pwd
RUN ls -la
RUN git fetch --all --recurse-submodules --tags
RUN git checkout tags/1.25.1

# Configure build options.
RUN cabal configure -O0 -w ghc-8.10.2

RUN cat /root/.cabal/config

# Update the cabal config, project settings, and reset build folder.
RUN echo -e "package cardano-crypto-praos\n flags: -external-libsodium-vrf" > cabal.project.local
RUN sed -i /root/.cabal/config -e "s/overwrite-policy:/overwrite-policy: always/g"
RUN rm -rf /tmp/cardano-node/dist-newstyle/build/x86_64-linux/ghc-8.10.2

# Build the cardano-node from source code.
RUN cabal build cardano-cli cardano-node

# Copy cardano-cli and cardano-node files into bin directory.
RUN cp $(find /tmp/cardano-node/dist-newstyle/build -type f -name "cardano-cli") /usr/local/bin/cardano-cli
RUN cp $(find /tmp/cardano-node/dist-newstyle/build -type f -name "cardano-node") /usr/local/bin/cardano-node

RUN cardano-node version
RUN cardano-cli version

# Install gLiveView, a monitoring tool.
WORKDIR $NODE_HOME
RUN apt-get update
RUN apt-get install iproute2
RUN apt install bc tcptraceroute -y
RUN curl -s -o gLiveView.sh https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/gLiveView.sh
RUN curl -s -o env https://raw.githubusercontent.com/cardano-community/guild-operators/master/scripts/cnode-helper-scripts/env
RUN chmod 755 gLiveView.sh

RUN sed -i env \
    -e "s/\#CONFIG=\"\${CNODE_HOME}\/files\/config.json\"/CONFIG=\"\/data\/configuration\/testnet-config.json\"/g" \
    -e "s/\#SOCKET=\"\${CNODE_HOME}\/sockets\/node0.socket\"/SOCKET=\"\/data\/node.socket\"/g"