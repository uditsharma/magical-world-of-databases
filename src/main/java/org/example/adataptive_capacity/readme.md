# This is prototype implementation of Adaptive Capacity
# This concept is used in DynamoDB to handle traffic spikes.
## How it works?
## In Dynamo DB a table has expeceted througput defined in terms of read and write capacity units.
## and this capacity is distributed among the partitions as equal based on assumption that each partition is accessed uniformly.
## But in real world this is not the case, some partitions are accessed more than others.
## So to handle this, DynamoDB has adaptive capacity feature.
## So what it does is it monitors the partitions and if it finds that some partitions are being accessed more than others, it will move the capacity from one partition to another.
## it uses the propotional control algorithm to do this.



