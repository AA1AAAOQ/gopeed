package http

// DefaultUserAgent is used when the configured user agent is empty.
const DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36"

// DefaultConnections is used when the configured connection count is invalid.
const DefaultConnections = 16

type ReqExtra struct {
	Method string            `json:"method"`
	Header map[string]string `json:"header"`
	Body   string            `json:"body"`
}

type OptsExtra struct {
	Connections int `json:"connections"`
	// AutoTorrent when task download complete, and it is a .torrent file, it will be auto create a new task for the torrent file
	// nil means use global config, true/false means explicit setting
	AutoTorrent *bool `json:"autoTorrent"`
	// DeleteTorrentAfterDownload when true, deletes the .torrent file after creating BT task
	// nil means use global config, true/false means explicit setting
	DeleteTorrentAfterDownload *bool `json:"deleteTorrentAfterDownload"`
	// AutoExtract when task download complete, and it is an archive file, it will be auto extracted
	// nil means use global config, true/false means explicit setting
	AutoExtract *bool `json:"autoExtract"`
	// ArchivePassword is the password for extracting password-protected archives
	ArchivePassword string `json:"archivePassword"`
	// DeleteAfterExtract when true, deletes the archive file after successful extraction
	DeleteAfterExtract bool `json:"deleteAfterExtract"`
}

// Stats for download
type Stats struct {
	// Total is the total size of the resource in bytes, 0 when unknown
	Total       int64              `json:"total"`
	Connections []*StatsConnection `json:"connections"`
}

// StatsConnection is the per connection progress of a running download.
type StatsConnection struct {
	// ID is the connection index, stable for the lifetime of the task
	ID int `json:"id"`
	// Role is one of resolve / primary / worker
	Role string `json:"role"`
	// State is one of notStarted / connecting / downloading / completed / failed
	State string `json:"state"`
	// Begin and End are the inclusive byte range the connection is responsible for
	Begin int64 `json:"begin"`
	End   int64 `json:"end"`
	// Downloaded is the bytes already written inside [Begin, End]
	Downloaded int64 `json:"downloaded"`
	// Speed is the recent speed of this connection in bytes per second
	Speed      int64 `json:"speed"`
	Completed  bool  `json:"completed"`
	Failed     bool  `json:"failed"`
	RetryTimes int   `json:"retryTimes"`
}
