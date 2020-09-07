import grpc

import sys
import checker_pb2
import checker_pb2_grpc

def run():

    if (str(sys.argv[1]) == "1"):
      # Go go outside.
      #
      channel = grpc.insecure_channel('dp-kub-1:30009')

    else:
      # Go local
      #
      channel = grpc.insecure_channel('localhost:50099')
    stub = checker_pb2_grpc.CheckerStub(channel)

    response = stub.getToy(checker_pb2.Person(firstName="Dennis", lastName="Periquet"))
    print("checker client received: " + response.item)
    print("checker client received: " + str(response.number))
if __name__ == '__main__':
    run()

