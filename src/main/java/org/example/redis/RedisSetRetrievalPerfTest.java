package org.example.redis;

import org.redisson.Redisson;
import org.redisson.api.*;
import org.redisson.config.Config;
import java.util.*;
import java.util.concurrent.TimeUnit;

public class RedisSetRetrievalPerfTest {
    private static final String SET_KEY = "test_set";
    private static final String CACHE_SET_KEY = "test_cache_set";
    private static final int[] TEST_SIZES = {
            100_000,    // 100K
            500_000,    // 500K
            1_000_000,  // 1M
            2_000_000   // 2M
    };
    private static final int BATCH_SIZE = 10_000;
    private static final int TEST_ITERATIONS = 5;
    private static final long CACHE_TTL = 3600; // 1 hour TTL

    private final RedissonClient redisson;

    public RedisSetRetrievalPerfTest() {
        Config config = new Config();
        config.useSingleServer()
                .setAddress("redis://localhost:6379")
                .setConnectionMinimumIdleSize(10)
                .setConnectionPoolSize(50)
                .setRetryAttempts(3)
                .setTimeout(30000); // Increased timeout for large datasets

        this.redisson = Redisson.create(config);
    }

    public void runTestSuite() {
        for (int size : TEST_SIZES) {
            System.out.printf("%n=== Testing with %,d elements ===%n", size);
            setup(size);
            runTests();
            cleanup();

            // Short pause between size tests
            try {
                Thread.sleep(5000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private void setup(int totalElements) {
        // Clear existing keys
        redisson.getKeys().delete(SET_KEY, CACHE_SET_KEY);

        RSet<String> set = redisson.getSet(SET_KEY);
        RSetCache<String> setCache = redisson.getSetCache(CACHE_SET_KEY);

        System.out.println("Starting data population...");
        long startTime = System.nanoTime();

        // Populate both sets in batches
        for (int i = 0; i < totalElements; i += BATCH_SIZE) {
            // Regular Set batch
            RBatch setBatch = redisson.createBatch();
            RSetAsync<String> setAsync = setBatch.getSet(SET_KEY);

            for (int j = 0; j < BATCH_SIZE && (i + j) < totalElements; j++) {
                setAsync.addAsync("member:" + (i + j));
            }
            setBatch.execute();

            // SetCache (can't use batch for TTL operations)
            for (int j = 0; j < BATCH_SIZE && (i + j) < totalElements; j++) {
                setCache.add("member:" + (i + j), CACHE_TTL, TimeUnit.SECONDS);
            }

            if ((i + BATCH_SIZE) % 100_000 == 0) {
                System.out.printf("Populated %,d elements%n", Math.min(i + BATCH_SIZE, totalElements));
            }
        }

        long duration = TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - startTime);
        System.out.printf("Data population completed in %d seconds%n", duration);

        // Verify sizes
        System.out.printf("Regular Set size: %,d%n", set.size());
        System.out.printf("Cache Set size: %,d%n", setCache.size());
    }

    private void runTests() {
        for (int i = 0; i < TEST_ITERATIONS; i++) {
            System.out.printf("%nIteration %d:%n", i + 1);

            // Test different retrieval methods
            testFullRetrieval();
            testIteratorRetrieval();

            // Short pause between iterations
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private void testFullRetrieval() {
        System.out.println("\nTesting full retrieval (readAll):");

        // Test RSet
        RSet<String> set = redisson.getSet(SET_KEY);
        long startTime = System.nanoTime();
        Set<String> setMembers = set.readAll();
        long setDuration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime);

        // Test RSetCache
        RSetCache<String> setCache = redisson.getSetCache(CACHE_SET_KEY);
        startTime = System.nanoTime();
        Set<String> cacheMembers = setCache.readAll();
        long cacheDuration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime);


        /*// Test RSetCache
        RSetCache<String> setCache2 = redisson.getSetCache(CACHE_SET_KEY);
        startTime = System.nanoTime();
        Set<String> cacheMembers2 = new HashSet<>(setCache2);
        long cacheDuration2 = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime);
*/
        // Print results
        System.out.printf("RSet:%n");
        System.out.printf("- Retrieved %,d members in %,d ms%n", setMembers.size(), setDuration);
        System.out.printf("- Throughput: %,.2f members/ms%n", (double) setMembers.size() / setDuration);


        System.out.printf("RSetCache:%n");
        System.out.printf("- Retrieved %,d members in %,d ms%n", cacheMembers.size(), cacheDuration);
        System.out.printf("- Throughput: %,.2f members/ms%n", (double) cacheMembers.size() / cacheDuration);

        double performanceDiff = ((double) cacheDuration / setDuration - 1) * 100;
        System.out.printf("RSetCache is %.1f%% %s than RSet%n",
                Math.abs(performanceDiff),
                performanceDiff > 0 ? "slower" : "faster");
    }

    private void testIteratorRetrieval() {
        System.out.println("\nTesting iterator retrieval:");

        // Test RSet iterator
        RSet<String> set = redisson.getSet(SET_KEY);
        long startTime = System.nanoTime();
        int setCount = 0;
        for (String member : set) {
            setCount++;
        }
        long setDuration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime);

        // Test RSetCache iterator
        RSetCache<String> setCache = redisson.getSetCache(CACHE_SET_KEY);
        startTime = System.nanoTime();
        int cacheCount = 0;
        for (String member : setCache) {
            cacheCount++;
        }
        long cacheDuration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime);

        // Print results
        System.out.printf("RSet Iterator:%n");
        System.out.printf("- Iterated %,d members in %,d ms%n", setCount, setDuration);
        System.out.printf("- Throughput: %,.2f members/ms%n", (double) setCount / setDuration);

        System.out.printf("RSetCache Iterator:%n");
        System.out.printf("- Iterated %,d members in %,d ms%n", cacheCount, cacheDuration);
        System.out.printf("- Throughput: %,.2f members/ms%n", (double) cacheCount / cacheDuration);

        double performanceDiff = ((double) cacheDuration / setDuration - 1) * 100;
        System.out.printf("RSetCache iterator is %.1f%% %s than RSet iterator%n",
                Math.abs(performanceDiff),
                performanceDiff > 0 ? "slower" : "faster");
    }

    private void cleanup() {
        redisson.getKeys().delete(SET_KEY, CACHE_SET_KEY);
    }

    public void shutdown() {
        redisson.shutdown();
    }

    public static void main(String[] args) {
        RedisSetRetrievalPerfTest perfTest = new RedisSetRetrievalPerfTest();
        try {
            perfTest.runTestSuite();
        } finally {
            perfTest.shutdown();
        }
    }
}
