package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/int128/oauth2cli"
	"github.com/int128/oauth2cli/oauth2params"
	"github.com/pkg/browser"
	"golang.org/x/oauth2"
	"golang.org/x/sync/errgroup"
)

// The following `transport` struct and its implemented `RoundTrip` function provide a workaround
// necessary when working with Azure Entra ID. To enable the authorization flow with PKCE,
// you must configure the Azure App Registration as a "Single Page Application" (SPA) variant.
// During the token retrieval step of the authentication flow, Azure requires the presence of an
// "Origin" header. The value of this header is not important; it just needs to be included.
type transport struct{}

func (t *transport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Set("Origin", "can-be-anything-does-not-matter")
	return http.DefaultTransport.RoundTrip(req)
}

func main() {

	/////////////////////////////////////////////////////////
	//              Change below two variables             //
	/////////////////////////////////////////////////////////
	tenantID := "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
	clientID := "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

	scopes := "api://term/access"

	pkce, err := oauth2params.NewPKCE()
	if err != nil {
		log.Fatalf("error: %s", err)
	}

	ready := make(chan string, 1)
	defer close(ready)

	cfg := oauth2cli.Config{
		OAuth2Config: oauth2.Config{
			ClientID: clientID,
			Endpoint: oauth2.Endpoint{
				AuthURL:  fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/authorize", tenantID),
				TokenURL: fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenantID),
			},
			Scopes: strings.Split(scopes, ","),
		},
		AuthCodeOptions:      pkce.AuthCodeOptions(),
		TokenRequestOptions:  pkce.TokenRequestOptions(),
		LocalServerReadyChan: ready,
	}

	// These two lines are a part of the Azure Entra ID workaround.
	// Creating a httpClient with the transport struct and adds it to the ctx variable.
	httpClient := &http.Client{Transport: &transport{}}
	ctx := context.WithValue(context.Background(), oauth2.HTTPClient, httpClient)

	errorGroup, ctx := errgroup.WithContext(ctx)
	errorGroup.Go(func() error {
		select {
		case url := <-ready:
			browser.Stdout = browser.Stderr
			if err := browser.OpenURL(url); err != nil {
				log.Printf("could not open the browser: %s", err)
			}
			return nil
		case <-ctx.Done():
			return fmt.Errorf("context done while waiting for authorization: %w", ctx.Err())
		}
	})

	errorGroup.Go(func() error {
		token, err := oauth2cli.GetToken(ctx, cfg)
		if err != nil {
			return fmt.Errorf("could not get a token: %w", err)
		}

		fmt.Fprintf(os.Stderr, "You got a valid token until %s\n\n", token.Expiry)

		if len(os.Args) > 1 {
			if os.Args[1] == "print-refresh-token" {
				fmt.Println(token.RefreshToken)
			}

			if os.Args[1] == "print-bearer" {
				jsonData, _ := json.MarshalIndent(token, "", "  ")
				fmt.Println(string(jsonData))
			}

			if os.Args[1] == "inspect-jwt" {
				url := fmt.Sprintf("https://jwt.io#token=%s", token.AccessToken)
				if err := browser.OpenURL(url); err != nil {
					log.Printf("could not open the browser: %s", err)
				}
				time.Sleep(1 * time.Second)
			}
		} else {
			fmt.Println(token.AccessToken)
		}
		return nil
	})
	if err := errorGroup.Wait(); err != nil {
		log.Fatalf("authorization error: %s", err)
	}
}
