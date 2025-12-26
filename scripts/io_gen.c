#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/uio.h>
#include <sys/fcntl.h>
#include <sys/ioctl.h>
#include <linux/fs.h>

#define SECTORSIZE 512
#define MAX_THREAD 16

typedef struct thread_argment_struct {
    int thread_id;
    char* device_name;
    int size;
    int epoch_width;
    int ios_per_epoch;
    int polling_flag;
    int total_runtime;
    char* mode_name;
} thread_argment_struct;

void* generator(void *arg) {
    thread_argment_struct *tas = (thread_argment_struct*) arg;
    char* device_name = tas->device_name;
    int size = tas->size;
    int epoch_width = tas->epoch_width;
    int ios_per_epoch = tas->ios_per_epoch;
    int polling_flag = tas->polling_flag;
    int total_runtime = tas->total_runtime;
    int thread_id = tas->thread_id;
    char* mode_name = tas->mode_name;

    int fd = open(device_name, O_RDONLY | O_DIRECT);
    if (fd < 0){
        printf("Fail\n");
        return 0;
    }

    void *buf = NULL;
    int ret = posix_memalign(&buf, SECTORSIZE, size);

    /*
     * linux/fs.h includes BLKGETSIZE64
     * Get device max lba
     */
    off64_t nvme_max_address; // in blocks
    ioctl(fd, BLKGETSIZE64, &nvme_max_address);
    nvme_max_address = nvme_max_address / SECTORSIZE;

    struct iovec iov;
    iov.iov_base = buf;
    iov.iov_len = size;

    struct timespec start_time, current, epoch_start;
    double runtime;
    double iops_time;
    int count = 0; // total IOs issued.
    int count_curr = 0; // IOs issued in this epoch.
    int count_missed_curr = 0; // IOs dropped in this epoch.
    int count_missed = 0; // total IOs dropped.
    double mean_duty = 0.0;
    int epoch_cnt = 0;
    int cnt_done;
    long long epoch_elapsed_time, duty_time; // us

    clock_gettime(CLOCK_MONOTONIC, &start_time);
    srand(time(NULL));
    for(;;){  // for each epoch
	epoch_cnt++;
	count_curr = 0;
        count_missed_curr = 0;	
        clock_gettime(CLOCK_MONOTONIC, &epoch_start);

	for(;;){ // issue up to "ios_per_epoch" I/Os, but within the time of epoch_width
	    if(count_curr < ios_per_epoch) {
               count++;
               count_curr++;
	       off_t offset = rand() % (nvme_max_address - 1);
               if (polling_flag){
                    // polling
                    ret = preadv2(fd, &iov, 1, offset * 512, RWF_HIPRI);
               } else{
                    // interrupt
                    ret = preadv2(fd, &iov, 1, offset * 512, 0);
               }
	    }
	    else // count_curr >= ios_per_epoch.
		    break;

	    // Calculate elapsed time since epoch start (unit: us)
            clock_gettime(CLOCK_MONOTONIC, &current);
	    epoch_elapsed_time = ((current.tv_sec - epoch_start.tv_sec) * 1000000000LL + (current.tv_nsec - epoch_start.tv_nsec)) / 1000LL;
            if (epoch_elapsed_time >  epoch_width) { // Running out of epoch time.
	    	if(count_curr < ios_per_epoch) {
		    count_missed_curr = ios_per_epoch - count_curr;
		    count_missed += count_missed_curr;
	    	}
                break;
	    }
        }
       
	clock_gettime(CLOCK_MONOTONIC, &current);
	duty_time = ((current.tv_sec - epoch_start.tv_sec) * 1000000000LL + (current.tv_nsec - epoch_start.tv_nsec)) / 1000LL;
//printf("epoch runtime: %Ld us ", duty_time);
	if(epoch_width > duty_time) {
//printf("Sleep %Ld us ", epoch_width - duty_time);
		usleep(epoch_width - duty_time);
	}

	mean_duty += duty_time / (double) epoch_width;
//printf("epoch_cnt: %d, issued IOs for this epoch: %d, missed IOs for this epoch: %d\n", epoch_cnt, count_curr, count_missed_curr);
	    
        // runtime check (sec, 10^0)
        runtime = ((current.tv_sec - start_time.tv_sec) * 1000000000.0 + (current.tv_nsec - start_time.tv_nsec)) / 1000000000.0;
        if (runtime >= total_runtime)
            break;
    }
    mean_duty = mean_duty / epoch_cnt;
    printf("%-10s epoch width: %-5dms mean_duty: %5.3lf target IOs per epoch: %-4d total IO count: %-8d, dropped: %-8d\n", mode_name, epoch_width / 1000, mean_duty, ios_per_epoch, count, count_missed);
    close(fd);
}

/*
 * ./a.out device_name size burst_io_count iops epoch_width epoch_width_time_based polling_flag total_runtime
 */
int main(int argc, char* argv[]){

    if(argc != 9) {
	    printf("Usage: $ %s [target device (ex: nvme2n1)] [IO size in KB (ex: 128)] [target IOPS (ex: 1000)] [epoch widh in us (ex: 320000 for 320ms)] [hipri (ex: 1 for hipri, 0 for no hipri)] [runtime in sec (ex: 10 for 10 sec)] [numjobs (not used for now. fix to 1)] [mode label]\n ", argv[0]);
	    printf("Ex) %s nvme2n1 128 1000 320000 1 3600 1 CP => run %s for 3600 sec to generate 128 KB random I/Os with 1,000 IOPS using preadv2(hipri).\n", argv[0], argv[0]);
	    exit(0);
    }

    char device_name[20] = "/dev/";
    strcat(device_name, argv[1]);

    int size = atoi(argv[2]) * 1024;
    int iops = atoi(argv[3]); // number of IOs per epoch
    int epoch_width = atoi(argv[4]); // in us
    int polling_flag = atoi(argv[5]);
    int total_runtime = atoi(argv[6]);
    int num_of_thread = atoi(argv[7]);
    char mode_name[20] = "";
    strcat(mode_name, argv[8]);

    pthread_t thread_array[MAX_THREAD];
    thread_argment_struct *thread_arg = (thread_argment_struct*)malloc(sizeof(thread_argment_struct));
    thread_arg->device_name = device_name;
    thread_arg->size = size;
    thread_arg->epoch_width = epoch_width; // unit: us
    thread_arg->ios_per_epoch = iops * (epoch_width / 1000) / 1000;
    thread_arg->polling_flag = polling_flag;
    thread_arg->total_runtime = total_runtime;
    thread_arg->mode_name = mode_name;
    printf("Run %s => dev: %s, size: %d, epoch_width: %d us, ios_per_epoch: %d, polling flag: %d, runtime: %d\n", 
		    argv[0], thread_arg->device_name,  thread_arg->size, thread_arg->epoch_width,
		    thread_arg->ios_per_epoch, thread_arg->polling_flag, thread_arg->total_runtime);
    //printf(" iops: %d epoch_width: %d thread_arg->ios_per_epoch : %d\n", iops, epoch_width  iops * (epoch_width / 1000) / 1000);

    for(int i=0; i<num_of_thread; i++) {
        thread_arg->thread_id = i;
        
        int thread_id = pthread_create(&thread_array[i], NULL, generator, thread_arg);
        usleep(50000);
        if(thread_id < 0) {
            perror("p_thread error");
            exit(0);
        }
    }
    // wait for last thread end
    pthread_join(thread_array[num_of_thread - 1], NULL);

    return 0;
}
