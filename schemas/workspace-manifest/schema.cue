package manifest

// Schema version for future compatibility
#Version: "1.0"

// Git remote definition (permissive to handle URLs, SSH, and local paths)
#RemoteURL: string & !=""

// Repository definition
#Repo: {
	path:           string & !=""
	default_branch: string & !="" | "unknown"
	remotes: {[string]: #RemoteURL} | *{}
}

// Workspace definition
#Workspace: {
	path: string & =~"^[a-zA-Z0-9_-]+$"
	repos: [...#Repo]
}

// Top-level manifest structure
#Manifest: {
	version:      #Version
	generated_at: string & !=""
	source_host:  string & !=""
	workspaces: {[string]: #Workspace}
}
