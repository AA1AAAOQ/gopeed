package http

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/GopeedLab/gopeed/internal/test"
	ph "github.com/GopeedLab/gopeed/pkg/protocol/http"
)

// TestStatsDebug is a diagnostic helper: it prints the per partition stats
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
	summary := func(tag string) {
		st := f.Stats().(*ph.Stats)
		done, partial, empty := 0, 0, 0
		var filled int64
		for _, c := range st.Connections {
			filled += c.Downloaded
			if c.Completed {
				done++
			} else if c.Downloaded == 0 {
				empty++
			} else {
				partial++
			}
		}
		fmt.Printf("%s segments=%d completed=%d partial=%d empty=%d filled=%d/%d\n",
			tag, len(st.Connections), done, partial, empty, filled, st.Total)
		if len(st.Connections) <= 6 {
			b, _ := json.Marshal(st)
			fmt.Println(tag+"_JSON", string(b))
		}
	}
	for i := 0; i < 30; i++ {
		summary("STATS_MID")
		time.Sleep(15 * time.Millisecond)
	}
	if err := f.Wait(); err != nil {
		t.Fatal(err)
	}
	summary("STATS_FINAL")
	fmt.Println("PROGRESS", f.Progress())
}