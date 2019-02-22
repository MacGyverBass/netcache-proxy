# Network Cache Docker Container

```txt
_____   __    ______________            ______
___/ | / /______/ /__/ ____/_____ _________/ /______
__/  |/ /_/ _ \/ __/  /    _/ __ `// ___/_/ __ \/ _ \
_/ /|  / /  __/ /_ / /___  / /_/ // /__ _  / / /  __/
/_/ |_/  \___/\__/ \____/  \__,_/ \___/ /_/ /_/\___/

```

## Introduction

This docker container provides a caching proxy server for game/internet download content.  For any network with more than one PC gamer downloading/updating games this will drastically reduce internet bandwidth consumption.  Even on networks with multiple Windows PCs downloading updates, this can also drastically reduce internet bandwidth consumtion.

This project is based off the work of [SteamCache](https://github.com/steamcache/steamcache)/[Generic](https://github.com/steamcache/generic)/[Monolithic](https://github.com/steamcache/monolithic), as well as [SNI Proxy](https://github.com/steamcache/sniproxy).  For more information, please check out their [GitHub steamcache Page](https://github.com/steamcache/).

In this project, Alpine was used instead of Ubuntu to keep the resulting image size lower and more lightweight.
Also changed is that SNI Proxy and nginx are both executed within this container, thus eliminating the need to execute it from yet another docker.

The primary use case is gaming events, such as LAN parties, which need to be able to cope with hundreds or thousands of computers receiving an unannounced patch - without spending a fortune on internet connectivity. Other uses include smaller networks, such as Internet Cafes and home networks, where the new games are regularly installed on multiple computers; or multiple independent operating systems on the same computer.

This container is designed to support any game that uses HTTP and also supports HTTP range requests (used by Origin). This should make it suitable for:

- Steam (Valve)
- Origin (EA Games)
- Riot Games (League of Legends)
- Battle.net (Hearthstone, Starcraft 2, Overwatch)
- Frontier Launchpad (Elite Dangerous, Planet Coaster)
- Uplay (Ubisoft)
- Windows Updates

This is the best container to use for all game caching and should be used for Steam in preference to the steamcache/steamcache and steamcache/generic containers.

## Usage

You need to be able to redirect HTTP traffic to this container. The easiest way to do this is to replace the DNS entries for the various game services with your cache server.

You can use the [netcache-dns](https://hub.docker.com/r/macgyverbass/netcache-dns/) or the [steamcache-dns](https://hub.docker.com/r/steamcache/steamcache-dns/) docker image to do this or you can use a DNS service already on your network.  See the [netcache-dns GitHub page](https://github.com/macgyverbass/netcache-dns) or the [steamcache-dns GitHub page](https://github.com/steamcache/steamcache-dns) for more information.

For the cache & log files to persist you will need to mount a directory on the host machine into the container. You can do this using `-v <path on host>:/data`.
Cache folders are created within `/data/cache` for each CDN service.  (Example: `/data/cache/steam`) -- This prevents any possible cross-CDN collisions and allows for easier disk-space usage or organization between the different service caches.

For example, you may decide to dedicate a single drive to steam, but cache all other CDNs onto another drive; you can even set your system up to cache the content on drives dedicated to each service.

Run the container using the following to allow TCP port 80 (HTTP), TCP port 443 (HTTPS), and to mount `/cache` directory into the container.

```sh
docker run --name netcache-proxy -p 10.0.0.2:80:80 -p 10.0.0.2:443:443 -v /cache:/data macgyverbass/netcache-proxy:latest
```

Unlike steamcache/generic this service will cache all CDN services (defined in the [uklans cache-domains repo](https://github.com/uklans/cache-domains) so multiple instances are not required.

Note: Like [netcache-dns](https://github.com/macgyverbass/netcache-dns), this supports custom domain lists to be cached.  Please review the GitHub page [macgyverbass/netcache-dns](https://github.com/macgyverbass/netcache-dns) for more information.

## Simple Full Stack startup

To initialise a full caching setup with DNS and SNI Proxy you can use the following script as a starting point:

```sh
DNS_IP="1.1.1.1 1.0.0.1"
HOST_IP=`hostname -I | head -n 1` # "10.0.0.2" in my test system
docker run --restart unless-stopped --name netcache-dns -p $HOST_IP:53:53/udp -e USE_GENERIC_CACHE=true -e LANCACHE_IP="$HOST_IP" -e UPSTREAM_DNS="$DNS_IP" macgyverbass/netcache-dns:latest
docker run --restart unless-stopped --name netcache-proxy -v /cache:/data -p $HOST_IP:80:80 -p $HOST_IP:443:443 -e UPSTREAM_DNS="$DNS_IP" macgyverbass/netcache-proxy:latest
echo Please configure your DHCP server to serve DNS as $HOST_IP
```

NOTE: Please check that `hostname -I` returns the correct IP before running this snippet.  You may need to supply this IP address manully.

## Changing from steamcache/generic and steamcache/monolithic

This new container is designed to replace an array of steamcache/generic containers with a single monolithic[*](https://github.com/steamcache/monolithic) instance.  This container is further designed to be a near drop-in replacement to steamcache/monolithic as well.

However if you currently run a steamcache/generic setup then there a few things to note:

1. Your existing cache files are NOT compatible with macgyverbass/netcache-proxy or steamcache/monolithic, thus your cache will not be recognized and will be rebuilt with the new folder layout and key entires.
2. You do not need multiple containers, a single netcache-proxy container (like monolithic) will cache ALL CDNs without collision.  NetCache-DNS takes this a step further than monolithic by placing each service cache into a different sub-folder.
3. macgyverbass/netcache-proxy (like steamcache/monolithic) should be compatible with your existing container's env vars so you can use the same run command you currently use, just change to macgyverbass/netcache-proxy.

## Origin and SSL

Some publishers, including Origin, use the same hostnames we're replacing for HTTPS content as well as HTTP content. We can't cache HTTPS traffic, so SNI Proxy will be used to forward traffic on port 443.

The netcache-proxy container comes with SNI Proxy built-in and runs alongside nginx, so while you do not need to run another docker container for sniproxy, you still need to assign the port when launching docker.

```sh
docker run --name netcache-proxy -p 10.0.0.2:80:80 -p 10.0.0.2:443:443 -v /cache:/data macgyverbass/netcache-proxy:latest
```

This runs the SNI Proxy on the same IP address as nginx.  Any HTTPS traffic will be forwarded directly to it's destination with caching.

## DNS Entries

You can find a list of domains you will want to use for each service over on [uklans/cache-domains](https://github.com/uklans/cache-domains). The aim is for this to be a definitive list of all domains you might want to cache.

## Suggested Hardware

Regular commodity hardware (a single 2TB WD Black on an HP Microserver) can achieve peak throughputs of 30MB/s+ using this setup (depending on the specific content being served).

## Changing Upstream DNS

If you need to change the upstream DNS server the cache uses, these are defined by the `UPSTREAM_DNS` environment variable.

It is recommended to provide this to netcache-proxy (as well as [netcache-dns](https://github.com/macgyverbass/netcache-dns)), as both nginx and SNI Proxy require a DNS resolver to be provided.  If not provided, it will fallback to any DNS entries found in the `/etc/resolv.conf` file.

You can provide these using the `-e` argument to docker run and specifying your upstream DNS servers. Multiple upstream DNS servers are allowed, separated by whitespace.

```txt
-e UPSTREAM_DNS="1.1.1.1 1.0.0.1"
```

## Tweaking Cache sizes

Two environment variables are available to manage both the memory and disk cache for a particular container, and are set to the following defaults.

```conf
CACHE_MEM_SIZE 500m
CACHE_DISK_SIZE 1000g
```

In addition, there is an environment variable to control the maximum cache age:

```conf
CACHE_MAX_AGE 3650d
```

You can override these at run time by adding the following to your docker run command.  They accept the standard nginx notation for sizes (k/m/g/t) and durations (m/h/d)

```txt
-e CACHE_MEM_SIZE=4g -e CACHE_DISK_SIZE=1t
```

**Note**: These values are per-service, please take this into consideration when running this container on lower spec systems.

## Monitoring

Access logs are written to `/data/logs`.  They are tailed by default in the main window when the container is launched.

You can also tail them using:

```sh
# Tail nginx access log:
docker exec -it netcache-proxy tail -f /data/logs/cache.log
# Tail sniproxy access log:
docker exec -it netcache-proxy tail -f /data/logs/sniproxy.log
# Tail nginx and sniproxy error log:
docker exec -it netcache-proxy tail -f /data/logs/error.log
```

If you have mounted the `/data` volume to `/cache` on the host, then you can tail it on the host instead.  For example:

```sh
tail /cache/logs/cache.log
tail /cache/logs/sniproxy.log
tail /cache/logs/error.log
```

## Testing/Debugging

There are two scripts included for testing nginx HTTP caching and sniproxy HTTPS forwarding.  These are called `cache_test.sh` and `https_test.sh`.

They can be executed while the docker is running:

```sh
# Check nginx HTTP caching:
docker exec -it netcache-proxy /scripts/cache_test.sh
# Check sniproxy HTTPS forwarding:
docker exec -it netcache-proxy /scripts/https_test.sh
```

## Advice to Publishers

If you are a games publisher and you like LAN parties, gaming centers and other places to be able to easily cache your game updates, we reccomend the following:

- If your content downloads are on HTTPS, you can do what Riot has done - try and resolve a specific hostname. If it resolves to a RFC1918 private address, switch your downloads to use HTTP instead.
- Try to use hostnames specific for your HTTP download traffic.
- Tell us the hostnames that you're using for your game traffic.  We're maintaining a list at [uklans/cache-domains](https://github.com/uklans/cache-domains) and we'll accept pull requests!
- Have your client verify the files and ensure the file it downloaded matches the file it **should** have downloaded. This cache server acts as a man-in-the-middle so it would be good to ensure the files are correct.

If you need any further advice, please contact [uklans.net](https://www.uklans.net/) for help.

## Frequently Asked Questions

If you have any questions, please check the [FAQs](FAQ.md). If this doesn't answer your question, please raise an issue in GitHub.

## Thanks

- Based on original container setup from [steamcache/monolithic](https://github.com/steamcache/monolithic).
- Based on original configs from [ti-mo/ansible-lanparty](https://github.com/ti-mo/ansible-lanparty).
- Everyone on [/r/lanparty](https://reddit.com/r/lanparty) who has provided feedback and helped people with this.
- UK LAN Techs for all the support.

## License

[The MIT License (MIT)](LICENSE)

