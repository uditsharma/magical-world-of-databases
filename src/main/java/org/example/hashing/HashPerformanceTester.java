package org.example.hashing;

import org.apache.commons.codec.digest.MurmurHash2;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.function.Function;

public class HashPerformanceTester {
    private static final int WARMUP_ITERATIONS = 100_000;
    private static final int TEST_ITERATIONS = 1_000_000;
    private static final int STRING_COUNT = 10_000;

    public static void main(String[] args) {
        // Generate test data
        List<String> testStrings = generateTestData();

        // Warmup JVM
        System.out.println("Warming up JVM...");
        warmup(testStrings);

        // Test hashCode()
        System.out.println("\nTesting String.hashCode()...");
        long hashCodeTime = benchmarkHash(testStrings, String::hashCode);

        // Test MurmurHash3
        System.out.println("\nTesting MurmurHash3...");
        long murmurTime = benchmarkHash(testStrings, MurmurHash2::hash32);

        // Print results
        System.out.println("\nResults:");
        System.out.printf("String.hashCode(): %d ms%n", hashCodeTime);
        System.out.printf("MurmurHash3: %d ms%n", murmurTime);
        System.out.printf("hashCode() is %.2fx %s than MurmurHash3%n",
                Math.abs((double) hashCodeTime / murmurTime),
                hashCodeTime < murmurTime ? "faster" : "slower");

        // Test collision rates
        System.out.println("\nTesting collision rates...");
        testCollisions(testStrings);
    }

    private static List<String> generateTestData() {
        List<String> strings = new ArrayList<>(STRING_COUNT);

        // Add various types of strings
        for (int i = 0; i < STRING_COUNT; i++) {
            // Mix of different string types
            switch (i % 4) {
                case 0:
                    // UUID-based strings
                    strings.add(UUID.randomUUID().toString());
                    break;
                case 1:
                    // Numeric strings
                    strings.add(String.valueOf(System.nanoTime()));
                    break;
                case 2:
                    // Random length strings
                    strings.add(generateRandomString(10 + i % 20));
                    break;
                case 3:
                    // URL-like strings
                    strings.add("https://example.com/path/" + i + "/" + UUID.randomUUID());
                    break;
            }
        }
        return strings;
    }

    private static String generateRandomString(int length) {
        StringBuilder sb = new StringBuilder(length);
        String chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        for (int i = 0; i < length; i++) {
            sb.append(chars.charAt((int) (Math.random() * chars.length())));
        }
        return sb.toString();
    }

    private static void warmup(List<String> strings) {
        for (int i = 0; i < WARMUP_ITERATIONS; i++) {
            for (String s : strings) {
                s.hashCode();
                MurmurHash2.hash32(s);
            }
        }
    }

    private static long benchmarkHash(List<String> strings, Function<String, Integer> hashFunction) {
        long startTime = System.currentTimeMillis();

        for (int i = 0; i < TEST_ITERATIONS; i++) {
            for (String s : strings) {
                hashFunction.apply(s);
            }
        }

        return System.currentTimeMillis() - startTime;
    }

    private static void testCollisions(List<String> strings) {
        int hashCodeCollisions = countCollisions(strings, String::hashCode);
        int murmurCollisions = countCollisions(strings, MurmurHash2::hash32);

        System.out.printf("hashCode() collisions: %d%n", hashCodeCollisions);
        System.out.printf("MurmurHash3 collisions: %d%n", murmurCollisions);
    }

    private static int countCollisions(List<String> strings, Function<String, Integer> hashFunction) {
        List<Integer> hashes = new ArrayList<>(strings.size());
        int collisions = 0;

        for (String s : strings) {
            int hash = hashFunction.apply(s);
            if (hashes.contains(hash)) {
                collisions++;
            }
            hashes.add(hash);
        }

        return collisions;
    }
}
