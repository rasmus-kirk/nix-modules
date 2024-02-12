{ config, ...}: 
with builtins;
let
  # Head function that will not panic.
  headMay = list: if list == [] then null else head list; 
  # Checks if string is ipv4, from SO, hope it works well
  # https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
  isIpv4 = address:
    let pat = "((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])";
        regex = match pat address;
    in regex != null;
  # Checks if string is ipv6, from SO, hope it works well
  # https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
  isIpv6 = address:
    let pat = "(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))";
        regex = match pat address;
    in regex != null;
  isIp = ip: (isIpv4 ip || isIpv6 ip);
  # Extracts dns servers from a wg-quick config file
  extractDns = wgConfPath: 
    let lines = split "\n" (readFile wgConfPath); 
        dnsLine = headMay (filter (x: typeOf x == "string" && match ".*DNS.*" x != null) lines); 
    in if dnsLine == null then [] else let
        ipsUnsplit = head (match "DNS ?=(.*)" dnsLine);
    in if ipsUnsplit == null then [] else let
        ips = filter (x: typeOf x == "string") (split "," ipsUnsplit);
        ipsNoSpaces = map (replaceStrings [" "] [""]) ips;
    in filter isIp ipsNoSpaces;
  # Extracts addresses from a wg-quick config file
  extractAddresses = wgConfPath: 
    let lines = split "\n" (readFile wgConfPath); 
        addrLine = headMay (filter (x: typeOf x == "string" && match ".*Address.*" x != null) lines); 
    in if addrLine == null then [] else let
        ipsUnsplit = head (match "Address ?=(.*)" addrLine);
    in if ipsUnsplit == null then [] else let
        ips = filter (x: typeOf x == "string") (split "," ipsUnsplit);
        ipsNoSpaces = map (replaceStrings [" "] [""]) ips;
    in filter isIp ipsNoSpaces;
  # Extracts the first ipv4 address from a wg-quick config file
  extractIpv4Address = wgConfPath:
    let ipv4s = filter isIpv4 (extractAddresses wgConfPath); in 
    headMay ipv4s;
  # Extracts the first ipv6 address from a wg-quick config file
  extractIpv6Address = wgConfPath:
    let ipv6s = filter isIpv6 (extractAddresses wgConfPath); in 
    headMay ipv6s;
  extractIpv4Dns = wgConfPath:
    let ipv4s = filter isIpv4 (extractDns wgConfPath); in 
    headMay ipv4s;
  # Extracts the first ipv6 address from a wg-quick config file
  extractIpv6Dns = wgConfPath:
    let ipv6s = filter isIpv6 (extractDns wgConfPath); in 
    headMay ipv6s;
in
{ 
  config.lib.util = {
    inherit 
      extractDns 
      extractAddresses 
      extractIpv4Address 
      extractIpv6Address 
      extractIpv4Dns 
      extractIpv6Dns 
      isIp
      isIpv4 
      isIpv6;
  };
}
