extends RefCounted
## DTLS for every ENet connection. The official server presents a CA-signed certificate for
## OFFICIAL_HOSTNAME and official clients verify it, so account credentials only ever reach the
## real server. Any other server (LAN tests, local development) uses the public development
## identity below: the link is encrypted, but anyone could present that identity, so callers must
## never send credentials to a non-official server.

const OFFICIAL_HOSTNAME := "ruellyya.kr"
const OFFICIAL_FALLBACK_ADDRESS := "211.176.222.145"
const OFFICIAL_LAN_ADDRESS := "192.168.0.4"
const CERT_ENV := "CATWAR_TLS_CERT"
const KEY_ENV := "CATWAR_TLS_KEY"
## Deliberately public, for development servers only. It proves nothing about who runs a server.
const DEV_CERT := """-----BEGIN CERTIFICATE-----
MIIDFDCCAfygAwIBAgIUGel/Swn3DAFEAfdEaOWLai3HyF8wDQYJKoZIhvcNAQEL
BQAwNzEVMBMGA1UEAwwMa2VlcGZhbGwtZGV2MREwDwYDVQQKDAhLZWVwZmFsbDEL
MAkGA1UEBhMCS1IwIBcNMjYwMTAxMDAwMDAwWhgPMjA5OTAxMDEwMDAwMDBaMDcx
FTATBgNVBAMMDGtlZXBmYWxsLWRldjERMA8GA1UECgwIS2VlcGZhbGwxCzAJBgNV
BAYTAktSMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArWcBZ7ojOyOC
8ImqUUcvo9t7qESThP2f/o2inXd/SDThOqFNIWWmaGKZYnLrJWtKQHR3I4BCCuLQ
d8e0EBpRzHfxp3b5RpI6BzPgHtzIKgqij7SUQeefiA5j0oj7Y2Td+nNzFnnMhlAw
s8L+Umfpem3nzcci3pj/Ox9P6M+EMhgAs6oAC2x4ZnNaPPM0MuVCm1YNMswe3Wb1
BSBu0M8eY06H5r6vXETqlGpNJ7vTQluBjZwDDrV8A+SMUrY98cgdey22215S0fid
NYTex+L9oJt7U76h/Ng7EHhwytzqfk/G4KCs01UUScY57RqtU+vJCoXuHbnXYm8j
7ONUqIbJzwIDAQABoxYwFDASBgNVHRMBAf8ECDAGAQH/AgEAMA0GCSqGSIb3DQEB
CwUAA4IBAQArXp3s+o4s9AOhuC4tfbrEYN34QnUYeou7AZwzOyUJjjlLhI3Zllqq
aK/Fh8JuvqOcl7FABBrJ0LgcW/x9pp94pLF57k9mXP3b9u77cs9sBBn5EcD3/NLq
TePi+S1Bij5oxNvtZgqiwmKmnmZaggRkWrOEN+aN5D7RlpqFmjEmJtV7+RSXfWYx
IPd9fhUUWKm11UOdSL2gvdXC2En+ztvQhrvz+1c4/gOPc/Ogl+PDPWwg5m1IRmVk
XImtz3zff33W5hisGAs2kamWIA+clhsAMaNlk+tmZ2tZf+ZcxG6B7Htte0S1WWZy
7Rq5HwKGT7bVKEdQXKPIMaZPUA8aGzXH
-----END CERTIFICATE-----"""
const DEV_KEY := """-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEArWcBZ7ojOyOC8ImqUUcvo9t7qESThP2f/o2inXd/SDThOqFN
IWWmaGKZYnLrJWtKQHR3I4BCCuLQd8e0EBpRzHfxp3b5RpI6BzPgHtzIKgqij7SU
QeefiA5j0oj7Y2Td+nNzFnnMhlAws8L+Umfpem3nzcci3pj/Ox9P6M+EMhgAs6oA
C2x4ZnNaPPM0MuVCm1YNMswe3Wb1BSBu0M8eY06H5r6vXETqlGpNJ7vTQluBjZwD
DrV8A+SMUrY98cgdey22215S0fidNYTex+L9oJt7U76h/Ng7EHhwytzqfk/G4KCs
01UUScY57RqtU+vJCoXuHbnXYm8j7ONUqIbJzwIDAQABAoIBAAGN/lGmsd59xX/1
n6C/P0E6KMOhnJssitONuVbWusIXImDJlDYhkl+RJpzGKFiXP9OYb3ZOcMDifZQv
qtuWXC1SpI7Ar0F2TXP7h8LpZdXEuYtsnakW5ZrpKPTLdxhefT3Xoo+l1SKqHPCC
PKDIUcjkFyyyMurFORqHJPxth98VSMwCoOCAPPIa9SckJr3n8BXvz8Jxs2Tbv+d6
rYoScamWUeNA5YrTCW5SgeJks86l3iBFnIBQTZiC8Ff+u26kuUUtojR2t0DGHa+k
Pt4sgRE7F4ZbFQrHZmmHthswzX+OK0F9ec4OKBxq4FySBzN6OOfo20J+UJJEmeZb
iO5HJHECgYEA5gEcHoy6v11D0HoGVrnOnyKhkXOEPYGohv1LhPdjdvzzmQrw/pV1
onon3SmNKvhfXcW4ebYr6thw246+lLYdmK1QHUFdSS7QcaMW2Sbntq/0MhaL/tCk
SVgQYxyeZixHyz/iOstU+PydeEwkQZCcuDAAkbVW9HFicItXWdR/imkCgYEAwQAw
Fs2LlNnWJwPAfYNVRLORNnltR3j8ECygFtHaPJ2Gt1xz3Bnp6nTheIZk9dfHxfo7
xSptDE93FZ7GUBPIPTnUtI69JuyOfwxL9QfWfXzuS/ehnrGRmny/hHuMNE6/NRqn
5nNy2BxBa2vkZ4mD/wRzQWW/KtCNEf+1MCI1e3cCgYEA1q6Eg5NRn9q6uHWdQwfN
b0XQzsWm0g4aslzsR2Dt6xsxeFD5Hnd8xDoGyWzGQixwP0OU6635EgwSUyzKgF34
BBEI7TWcj/ltQBQ8+FVTBHb5lGLtKtut7HORYCFPTAjavkCTtdMiLgEELkvLr5L+
ZQERFu/PCPxoKKo2zzcEELkCgYBAwLNhsyy1kDCNfnDCq6GcHzMFN9A2Pp0zQAWm
Ilo6JA/izR4CJp+YjgZnzY9p/C+GeOI80HMtwiuOEWsvyrNP92sp+Qn1WUCl15ZU
a4DHMXcx/a838xOK5XfMFzd/BTyZsIvMgcdyQmighd5n7ndexDt3IY/16WqrM0Oz
FocjGQKBgDLB5RE7qZ8hj2SISBUuVyCDF4czTB/SYayBhvD0bilrhb57Z8XQcDEM
blAPsFZmB1cuoHN17TDCfjvJD/TpuNHLVjiHNlTRQWlCocqAoeM+iXk2+642mSLl
jJcTIMp0Oappbk1gVjMGYZ25KgeImJj3UGMAYJvy96IQWQ5ZkzYe
-----END RSA PRIVATE KEY-----"""

## The server identity: the PEM pair named by CATWAR_TLS_CERT/CATWAR_TLS_KEY (for example a
## Let's Encrypt fullchain/privkey), else the public development pair. Returns null when a
## configured pair cannot be read, so a broken production setup never silently downgrades.
static func server_options() -> TLSOptions:
	var cert_path := OS.get_environment(CERT_ENV).strip_edges()
	var key_path := OS.get_environment(KEY_ENV).strip_edges()
	var cert := X509Certificate.new()
	var key := CryptoKey.new()
	if cert_path.is_empty() and key_path.is_empty():
		cert.load_from_string(DEV_CERT)
		key.load_from_string(DEV_KEY)
		print("TLS_CERTIFICATE development: official clients refuse this server until %s and %s are set" % [CERT_ENV, KEY_ENV])
		return TLSOptions.server(key, cert)
	if cert.load(cert_path) != OK or key.load(key_path) != OK:
		printerr("TLS_CONFIG_INVALID cert=%s key=%s" % [cert_path, key_path])
		return null
	print("TLS_CERTIFICATE configured")
	return TLSOptions.server(key, cert)

static func is_official_address(address: String) -> bool:
	return address.strip_edges().to_lower() in [OFFICIAL_HOSTNAME, OFFICIAL_FALLBACK_ADDRESS, OFFICIAL_LAN_ADDRESS]

## Official addresses (including the bare IP and LAN address) are verified as OFFICIAL_HOSTNAME.
static func client_hostname(address: String) -> String:
	return OFFICIAL_HOSTNAME if is_official_address(address) else address.strip_edges()

static func client_options(address: String) -> TLSOptions:
	if is_official_address(address):
		return TLSOptions.client()
	var chain := X509Certificate.new()
	chain.load_from_string(DEV_CERT)
	return TLSOptions.client_unsafe(chain)
