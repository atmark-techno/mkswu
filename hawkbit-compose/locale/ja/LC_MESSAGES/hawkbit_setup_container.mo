Þ    X      Ü                  B   ³     ö       >   !  #   `  ?     j   Ä     /	  A   H	     	  	   	  [   §	  8   
     <
     P
     k
  "   
     «
  !   Æ
  *   è
  !        5     O  :   o  -   ª  =   Ø  2     7   I  ,     $   ®  +   Ó     ÿ  '     8   G       0      Q   Ñ  M   #  U   q  5   Ç  6   ý     4     L     ^  C   x  C   ¼        '        F     d  .   t  ?   £  e   ã  5   I               ²  D   É  J     9   Y  A        Õ  D   í  [   2  >     Z   Í     (  ;   B  ,   ~  Y   «  <     -   B  5   p  9   ¦  F   à  E   '  N   m  ?   ¼     ü          7  >   ;     z  5     L   À  F     (   T      }  N     *   í       l   .  -     e   É     /     ¿  p   Ù  /   J  !   z       Z   #  0   ~  0   ¯  S   à  <   4  6   q  *   ¨  Q   Ó  3   %  -   Y  9     V   Á  U     L   n  P   »  [      >   h   R   §   ,   ú   *   '!  `   R!  ;   ³!  7   ï!  6   '"  d   ^"  J   Ã"     #  y   ¡#  l   $  $   $  '   ­$  #   Õ$  f   ù$  W   `%  9   ¸%  C   ò%  0   6&  *   g&  +   &  r   ¾&  t   1'  N   ¦'  ,   õ'  ,   "(  /   O(  d   (  S   ä(  O   8)  b   )     ë)  ]    *     ^*  ?   ß*     +  )   ¬+  H   Ö+  Z   ,  K   z,  J   Æ,  ^   -  V   p-  \   Ç-  X   $.  l   }.  |   ê.  T   g/  -   ¼/  *   ê/     0  X   0      r0  K   0  ;   ß0  U   1              (   :       "   $   E   >       	          K   )   '       X              T           <          6       C          7           1      V       8   A       5          U   @       W                            J              S       2                     O   %       G   R   0      !       3   L   Q   +   /              4   ;   =   B   9   F      
          #          .       ?         P   D                   N   I   -   &                  *   ,   M   H               $arg requires an argument $fragment_pattern did not match anything in $name source fragments $user already exists! A value is required. Allow user to handle rollouts? (trigger installation requests) Also disallow token authentication? CA file path (leave empty to disable client TLS authentication) Certificate domain name changed (found $current_domain, expected $REVERSE_PROXY_CERT_DOMAIN), regenerating Certificate domain name: Checking if container is running... ${SUDO:+(this requires sudo)} Confirm password:  Continue? Continuing without let's encrypt. Run again with --letsencrypt if you want to add it later. Could not connect to docker daemon, trying with sudo...  Could not copy file Could not create directory Could not create script link Could not disable lighttpd service Could not enter config dir Could not generate $file fragment Could not make symlink to new certificates Could not remove old certificates Could not stop containers Could not stop lighttpd service Could not update user id in hawkBit application.properties Could not use docker, is the service running? Could not verify that this host is suitable for let's encrypt Create hawkBit device user? (for autoregistration) Create hawkBit mkswu user? (for automated image upload) Creating link to $SCRIPT_BASE in $CONFIG_DIR Docker is not installed. Install it? Email to use for let's encrypt registration Empty passwords are not allowed Extra admin user name (empty to stop):  Failed aggregating fragments ${fragments[*]} to $tmpdest Failed moving $tmpdest to $dest How long should the certificate be valid (days)? If the host is directly accessible over internet, it it possible to setup a let's If you would like to setup client certificate authenication a ca is required. Install failed, please check https://docs.docker.com/get-docker/ and install manually Install failed, please install apache2-utils manually Install failed, please install docker-compose manually Password for user $user Password mismatch Please answer with y or n Please check https://docs.docker.com/get-docker/ and install docker Please check the machine is reachable at $REVERSE_PROXY_CERT_DOMAIN Please install docker-compose Please install htpasswd (apache2-utils) Please stop lighttpd manually Removing users: Setup certbot container to obtain certificate? Setup finished! Use docker-compose now to manage the containers Should you want to use a let's encrypt certificate, you can run $SCRIPT_BASE again with --letsencrypt Start containers once and run the following commands: Start hawkBit containers? Stop hawkBit containers? Stop lighttpd service? TLS certificate have a lifetime that must be set. If you plan to use The recommended way of doing this is including this base64-encoded copy of The reverse proxy needs a domain name for the certificate This MUST be the domain name as reachable from devices, so if the Unhandled arguments: $@ Where should we store docker-compose configuration and hawkBit data? You need to copy $CERT to /usr/local/share/ca-certificates/ and run update-ca-certificates. and if your url is https://10.1.1.1 then it should be 10.1.1.1 ca file $REVERSE_PROXY_CLIENT_CERT does not exist. Reset proxy settings with --reset-proxy certbot invocation failed certificate validity must be a number of days (only digits) docker-compose is not installed. Install it? encrypt certificate instead of the self-signed one. Accepting means you agree to the TOS: hawkBit containers seem to be running, updating config files hawkBit had no user defined, create one first htpasswd failed for given password - missing command? htpasswd is required for password generation. Install it? is generated and can be left to its default value. Best practice would let's encrypt, this value will only be used until the new certificate letsencrypt setup requires running containers once for configuration, run now? lighttpd is running and conflicts with the reverse proxy setup. might not work as expected. nginx container not coming up! ok! or run $CONFIG_DIR/$SCRIPT_BASE again to change configuration. realpath failed require generating a new certificate every few years. the certificate into the example's hawkbit_register.sh script SSL_CA_BASE64: url will be https://hawkbit.domain.tld it should be hawkbit.domain.tld Content-Type: text/plain; charset=UTF-8
 $arg ã«å¼æ°ãå¿è¦ã§ãã $fragment_pattern ã¯ $name ã® fragments ã«è¦ã¤ããã¾ããã§ããã $user ã¯ãã§ã«ç»é²ããã¦ã¾ãã å¤ãå¿è¦ã§ãã ã¦ã¼ã¶ã¼ã«ã­ã¼ã«ã¢ã¦ãã®æ¨©éãä¸ãã¾ããï¼ï¼ã¤ã³ã¹ãã¼ã«è¦æ±ãåºããã¨ï¼ ãã¼ã¯ã³èªè¨¼ãç¡å¹ã«ãã¾ããï¼ ç½²åCAã®ãã¡ã¤ã«ãã¹ï¼ç©ºã«ããã¨ã¯ã©ã¤ã¢ã³ãTLSèªè¨¼ãç¡å¹ã«ãªãã¾ãï¼ è¨¼ææ¸ã® domain nameããããã¾ãããåä½æãã¾ããï¼$current_domain ã§ããã $REVERSE_PROXY_CERT_DOMAIN ã«ãã¾ãï¼ è¨¼ææ¸ã® domain name: ã³ã³ãããèµ·åããã¦ããã©ãããç¢ºèªãã¾ã... ${SUDO:+(sudoãã¹ã¯ã¼ããå¿è¦ã§ã)} ãã¹ã¯ã¼ããåå¥åãã¦ãã ãã:  ãã®ã¾ã¾å®è¡ãã¾ããï¼ Let's encryptãªãã§å®è¡ãã¾ãã--letsencryptãä»ãã¦ååº¦å®è¡ããã¨ãå¾ããè¿½å ãããã¨ãå¯è½ã§ãã docker ãµã¼ãã¹ã«æ¥ç¶ã§ãã¾ããã§ãããsudo ã§ããä¸åº¦è©¦ãã¾ãã ãã¡ã¤ã«ã®ã³ãã¼ã«å¤±æãã¾ããã ãã£ã¬ã¯ããªä½æãå¤±æãã¾ããã ã¹ã¯ãªããã® ã·ã³ããªãã¯ãªã³ã¯ ãä½æã§ãã¾ããã§ããã lighttpd ãµã¼ãã¹ãç¡å¹ã«ã§ãã¾ããã§ããã è¨­å®ãã£ã¬ã¯ããªã«å¥ãã¾ããã§ããã $file ãä½æã§ãã¾ããã§ããã æ°ããè¨¼ææ¸ã®ã·ã³ããªãã¯ãªã³ã¯ããä½ãã¾ããã§ããã åã®è¨¼ææ¸ãåé¤ã§ãã¾ããã§ããã ã³ã³ãããåæ­¢ã§ãã¾ããã§ãã lighttpd ãµã¼ãã¹ãåæ­¢ã§ãã¾ããã§ããã hawkBit application.propertiesã®ã¦ã¼ã¶ã¼ã®IDãæ´æ°ã§ãã¾ããã§ããã docker ãå®è¡ã§ãã¾ããã§ããããµã¼ãã¹ãèµ·åãã¦ãã¾ããï¼ ãã®ãã·ã³ã§Let's encryptã®å©ç¨ç¢ºèªãåãã¾ããã§ããã hawkBit ã®ãdeviceãã¦ã¼ã¶ã¼ãç»é²ãã¾ããï¼ï¼èªåç»é²ç¨ï¼ hawkBit ã®ãmkswuãã¦ã¼ã¶ã¼ãç»é²ãã¾ããï¼ï¼swuã®ã¢ããã­ã¼ãç¨ï¼ $SCRIPT_BASE ã¸ã®ãªã³ã¯ã $CONFIG_DIR ã«ä½ãã¾ãã Docker ã¯ã¤ã³ã¹ãã¼ã«ããã¦ã¾ãããã¤ã³ã¹ãã¼ã«ãã¾ããï¼ Let's encrypt ç»é²ã®ã¡ã¼ã«ã¢ãã¬ã¹ ç©ºã®ãã¹ã¯ã¼ãã¯ä½¿ãã¾ããã è¿½å ã®ç®¡çäººã¢ã«ã¦ã³ãã®ã¦ã¼ã¶ã¼ãã¼ã ï¼ç©ºã«ããã¨è¿½å ãã¾ããï¼ ${fragments[*]} ã $tmpdest ã«æ¸ãã¾ããã§ããã $tmpdest ã $dest ã«ç§»åã§ãã¾ããã§ããã è¨¼ææ¸ã®æå¹æéã¯ä½æ¥éã«ãã¾ããï¼ ãµã¼ãã¼ãç´æ¥ã¤ã³ã¿ãããã«ã¢ã¯ã»ã¹å¯è½ã§ããã°ãLet's Encryptã®è¨¼ææ¸ ã¯ã©ã¤ã¢ã³ãã®TLSèªè¨¼ãè¨­å®ããããã«CAãå¿è¦ã§ãã Docker ã®ã¤ã³ã¹ãã¼ã«ãå¤±æãã¾ããã https://docs.docker.com/get-docker/ ãåèã«ãã¦ã¤ã³ã¹ãã¼ã«ãã¦ãã ããã apache2-utils (htpasswd) ãã¤ã³ã¹ãã¼ã«ã§ãã¾ããã§ãããæåã§ã¤ã³ã¹ãã¼ã«ãã¦ãã ããã docker-compose ã®ã¤ã³ã¹ãã¼ã«ãå¤±æãã¾ãããæåã§ã¤ã³ã¹ãã¼ã«ãã¦ãã ããã $user ã¦ã¼ã¶ã¼ã®ãã¹ã¯ã¼ã ãã¹ã¯ã¼ããä¸è´ãã¾ããã y ã n ã§ç­ãã¦ãã ããã https://docs.docker.com/get-docker/ ãåèã«ãã¦dockerãã¤ã³ã¹ãã¼ã«ãã¦ãã ããã $REVERSE_PROXY_CERT_DOMAIN ã«ã¢ã¯ã»ã¹ã§ãããã¨ãç¢ºèªãã¦ãã ããã docker-compose ãã¤ã³ã¹ãã¼ã«ãã¦ãã ããã htpasswd (apache2-utils) ãã¤ã³ã¹ãã¼ã«ãã¦ãã ããã lighttpd ãæåã§åæ­¢ãã¦ãã ããã ä»¥ä¸ã®ã¦ã¼ã¶ã¼ãæ¶ãã¾ãï¼
$* certbotã³ã³ãããè¨­å®ãã¾ããï¼ ã³ã³ããã®è¨­å®ãå®äºãã¾ãããdocker-compose ã³ãã³ãã§ã³ã³ããã®ç®¡çãå¯è½ã§ãã Let's encryptã®è¨­å®ã¯å¾ã§è¶³ãããå ´åã«setup_container.shã--letsencryptã§å®è¡ãã¦ãã ããã ã³ã³ãããèµ·åãã¦ä»¥ä¸ã®ã³ãã³ããå®è¡ãã¦ãã ããï¼ hawkBit ã³ã³ãããèµ·åãã¾ããï¼ hawkBit ã³ã³ãããåæ­¢ãã¾ããï¼ lighthttpd ãµã¼ãã¹ãåæ­¢ãã¾ããï¼ è¨¼ææ¸ã®æå¹æéãæå®ããå¿è¦ãããã¾ããLet's encryptãä½¿ç¨ããå ´åã ãã®base64ã§ã¨ã³ã³ã¼ããããã³ãã¼ãexamples/hawkbit_register.sh ã® ãªãã¼ã¹ãã­ã­ã·ã®è¨­å®ã«è¨¼ææ¸ã® domain name ãå¿è¦ã§ãã ãã® domain ã¯ãã®ã¾ã¾ããã¤ã¹ããã¢ã¯ã»ã¹ã§ããååã«ãã¦ãã ããã ä¸è¦ãªå¼æ°ï¼$@ docker-compose ã®è¨­å®ãã¡ã¤ã«ã¨ hawkBit ã®ãã¼ã¿ãã©ãã«ä¿å­ãã¾ããï¼ $CERT ã /usr/local/share/ca-certificates/ ã«ã³ãã¼ãã¦ã update-ca-certificates ãå®è¡ããå¿è¦ãããã¾ãã https://10.1.1.1 ã§ããã 10.1.1.1 ã«ãã¦ãã ããã $REVERSE_PROXY_CLIENT_CERT CA ãã¡ã¤ã«ãå­å¨ãã¾ããããã­ã­ã·ã®è¨­å®ãã--reset-proxy ã§åæåãã¦ãã ããã certbot ã®å®è¡ãå¤±æãã¾ããã è¨¼ææ¸ã®æå¹æéã¯æ¥æ°ã«ãã¦ãã ããï¼æ°å­ã®ã¿ï¼ docker-compose ã¯ã¤ã³ã¹ãã¼ã«ããã¦ã¾ãããã¤ã³ã¹ãã¼ã«ãã¾ããï¼ ãè¨­å®ãããã¨ãã§ãã¾ããTOSã¸ã®åæãæå³ãã¾ãã hawkBit ã³ã³ãããèµ·åãã¦ãã¾ãããã®ã¾ã¾å®è¡ããã¨ hawkBitã«ã¦ã¼ã¶ã¼ãããã¾ããã§ãããã¦ã¼ã¶ã¼ãè¿½å ãã¦ãã ããã htpasswdãå¤±æãã¾ãããã³ãã³ããã¤ã³ã¹ãã¼ã«ããã¦ã¾ããï¼ ãã¹ã¯ã¼ãä½æã®ããã«htpasswdãå¿è¦ã§ããã¤ã³ã¹ãã¼ã«ãã¾ããï¼ ã®ã¾ã¾ã«ãã¦ãããã¨ãã§ãã¾ããLet's encryptãä½¿ç¨ããªãå ´åã ãã®å¤ã¯æ°ããè¨¼ææ¸ãçæãããã¾ã§ããä½¿ç¨ãããªãã®ã§ãããã©ã«ãã®å¤ Let's encryptã®åæè¨­å®ã®ããä¸åº¦ã³ã³ãããèµ·åããå¿è¦ãããã¾ããããã«å®è¡ãã¾ããï¼ lighttpd ãèµ·åä¸­ã§ããªãã¼ã¹ãã­ã­ã·è¨­å®ã¨ç«¶åãã¦ãã¾ãã ã¨ã©ã¼ãåºãå¯è½æ§ãããã¾ãã nginx ã³ã³ãããèµ·åãã¾ããï¼ OK! $CONFIG_DIR/setup_container.sh ãåã³å®è¡ããã¨è¨­å®ã®å¤æ´ãå¯è½ã§ãã realpathãå¤±æãã¾ããã æ°å¹´ãã¨ã«è¨¼ææ¸ãæ°ãããããã¨ãæãå¥½ã¾ãã§ãã SSL_CA_BASE64 ã«æå®ããæé ãæ¨å¥¨ããã¾ãã ä¾ãã°ãhttps://hawkbit.domain.tld ã§ã¢ã¯ã»ã¹ããã hawkbit.domain.tldã 