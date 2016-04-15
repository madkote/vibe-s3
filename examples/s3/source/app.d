import vibe.d;

import vibe.aws.aws;
import vibe.aws.credentials;
import vibe.aws.s3;
import std.process : environment;

import core.sync.mutex;
import std.array;

shared static this()
{
//    setLogLevel(LogLevel.trace);

    //Use the environment variables "AWS_ACCESS_KEY_ID",
    //"AWS_SECRET_KEY", "S3_EXAMPLE_BUCKET" and "S3_EXAMPLE_REGION"
    //to configure this example.

    auto creds = new EnvAWSCredentials;
    auto bucket = environment.get("S3_EXAMPLE_BUCKET");
    auto region = environment.get("S3_EXAMPLE_REGION");

    auto cfg = ClientConfiguration();
    cfg.maxErrorRetry = 1;
    auto s3 = new S3(bucket,region,creds,cfg);

    auto mutex = new Mutex;
    auto condition = new TaskCondition(mutex);
    int runningTasks = 3;

    setTimer(1.seconds, {
        synchronized(mutex)
            runningTasks++;

        scope(exit)
            synchronized(mutex)
                if (--runningTasks == 0)
                    condition.notify();

        auto directories = appender!string;
        auto files = appender!string;

        string marker = null;
        while(true)
        {
            auto result = s3.list("/",null,marker,2);
            foreach(directory; result.commonPrefixes)
                directories.put(directory~"\n");

            foreach(file; result.resources)
                files.put(file.key~"\n");

            if (result.isTruncated)
                marker = result.nextMarker;
            else
                break;
        }

        logInfo("List (w/ directories):\n" ~ directories.data ~ files.data);
    });

    setTimer(1.seconds, {
        synchronized(mutex)
            runningTasks++;

        scope(exit)
            synchronized(mutex)
                if (--runningTasks == 0)
                    condition.notify();

        auto files = appender!string;

        string marker = null;
        while(true)
        {
            auto result = s3.list("/",null,marker);
            foreach(file; result.resources)
                files.put(file.key~"\n");

            if (result.isTruncated)
                marker = result.nextMarker;
            else
                break;
        }

        logInfo("List (w/o directories):\n" ~
                files.data);
    });

    setTimer(1.seconds, {
        synchronized(mutex)
            runningTasks++;

        scope(exit)
            synchronized(mutex)
                if (--runningTasks == 0)
                    condition.notify();

        logInfo("Starting upload...");
        s3.upload("test.txt", openFile("test.txt"), "text/plain");
        logInfo("Upload complete.");
    });

    setTimer(1.msecs, {
        synchronized(mutex)
            while(true)
            {
                condition.wait();
                if (runningTasks == 0)
                {
                    exitEventLoop();
                    break;
                }
            }
    });
}
