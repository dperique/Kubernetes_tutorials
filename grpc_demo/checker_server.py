from concurrent import futures

import time
import os
import grpc

import checker_pb2
import checker_pb2_grpc

class CheckerService(checker_pb2_grpc.CheckerServicer):

    def getToy(self, request, context):
        msg = "Trying to get toy for, {} {}!".format(request.firstName, request.lastName);
        podInfo = "iPhone 8s, %s, %s" % (os.environ.get('MY_POD_NAME'), os.environ.get('MY_NODE_NAME'))
        return checker_pb2.ToyItem(item=podInfo, number=2)

def serve():
  server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
  checker_pb2_grpc.add_CheckerServicer_to_server(CheckerService(), server)
  server.add_insecure_port('[::]:50099')
  server.start()
  try:
    while True:
      time.sleep(500)
  except KeyboardInterrupt:
    server.stop(0)


if __name__ == '__main__':
  serve()
