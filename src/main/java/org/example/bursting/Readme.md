### This is concept used to handle the temporary spike in dynamodb.
### Each parition has two token bucket one is allocated capacity and other is unused capacity in from task token buckets.
## And then there is node level token bucket so that we do not overload the system more than it can handle based on its resources
## when a  request lands on storage node, it first check whether the parition allocated bucket has token it
## then it will deduct the token from allocated bucket and node token buckets and process the request
## but if allocated buckets does not have capacity in it, then it will get the token from burst token bucket and check if node bucket has the capacity left
## if it has then it will process the request otherwise it will reject the request.
