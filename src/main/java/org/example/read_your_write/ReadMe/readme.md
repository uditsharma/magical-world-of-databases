### Imagine you have postgres setup master and few replicas, how will you make sure that you always read current data ?
### One option is that you always read from master, but this will put load on master.
### Other option is that you read from replicas, but this will give you stale data.(as there might be a replication lag)
### So how do you make sure that you always read current data and also not put load on master ?
### One way to do this is to use read your write consistency model.
### In this model, you always write to master and read from replicas.
### But before reading from replicas, you make sure that the data you wrote is available on replicas.
### This can be done by using a timestamp or a sequence number.
### In postgres when you write data to WAL you get LSN, and we can store this information somehwere and whenever we get query for that user 
### we can always fetch this LSN and select the replica which has read atleast copied till this LSN.
### This way you will always read current data and also not put load on master.
### How do you get the LSN number from postgres db ? Please write the query .

Questions:
-> LSN Stored is old then i can choose any replica and it is possible that i might not get fresh state of data.
