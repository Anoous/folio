package worker

import (
	"github.com/hibiken/asynq"
)

type WorkerServer struct {
	server *asynq.Server
	mux    *asynq.ServeMux
}

func NewWorkerServer(redisAddr string, crawl *CrawlHandler, ai *AIHandler, image *ImageHandler, echo *EchoHandler, push *PushHandler, relate *RelateHandler) *WorkerServer {
	srv := asynq.NewServer(
		asynq.RedisClientOpt{Addr: redisAddr},
		asynq.Config{
			Concurrency: 10,
			Queues: map[string]int{
				QueueCritical: 6,
				QueueDefault:  3,
				QueueLow:      1,
			},
		},
	)

	mux := asynq.NewServeMux()
	mux.HandleFunc(TypeCrawlArticle, crawl.ProcessTask)
	mux.HandleFunc(TypeAIProcess, ai.ProcessTask)
	if image != nil {
		mux.HandleFunc(TypeImageUpload, image.ProcessTask)
	}
	if echo != nil {
		mux.HandleFunc(TypeEchoGenerate, echo.ProcessTask)
	}
	if push != nil {
		mux.HandleFunc(TypePushEcho, push.ProcessTask)
	}
	if relate != nil {
		mux.HandleFunc(TypeRelateArticle, relate.ProcessTask)
	}

	return &WorkerServer{server: srv, mux: mux}
}

func (w *WorkerServer) Run() error {
	return w.server.Run(w.mux)
}

func (w *WorkerServer) Shutdown() {
	w.server.Shutdown()
}
