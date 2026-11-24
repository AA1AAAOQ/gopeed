package http

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/GopeedLab/gopeed/internal/test"
	ph "github.com/GopeedLab/gopeed/pkg/protocol/http"
)

// TestStatsDebug is a diagnostic helper: it prints the per connection stats
// during and after a download, so the segmented progress bar data can be
// verified against a real fetch.
func TestStatsDebug(t *testing.T) {
	listener := test.StartTestFileServer()
	defer listener.Close()

	f := downloadReady(listener, 8, t)
	t.Logf("resource size=%d range=%v", f.Meta().Res.Size, f.Meta().Res.Range)
	if err := f.Start(); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 40; i++ {
		st := f.Stats().(*ph.Stats)
		b, _ := json.Marshal(st)
		if len(b) > 1500 {
			b = b[:1500]
		}
		fmt.Println("STATS_MID", string(b))
		time.Sleep(10 * time.Millisecond)
	}
	if err := f.Wait(); err != nil {
		t.Fatal(err)
	}
	st := f.Stats().(*ph.Stats)
	b, _ := json.Marshal(st)
	fmt.Println("STATS_FINAL", string(b))
	fmt.Println("PROGRESS", f.Progress())
}