[private]
default:
	@just --list

# Prints the retrived jwt token
print-jwt:
  @go run -C go-cli main.go

# Prints the retrived Bearer token
print-bearer:
  @go run -C go-cli main.go print-bearer

# Prints the retrived refresh token
print-refresh-token:
  @go run -C go-cli main.go print-refresh-token

# Opens jwt.io with the retrived jwt token
inspect-jwt:
  @go run -C go-cli main.go inspect-jwt

# Gets a jwt token and makes a post to the URL provides. (URL to termpad)
post url:
  @curl -H "Authorization: Bearer $(just print-jwt)" -L -d "$(date): Hello World!" {{ url }}
