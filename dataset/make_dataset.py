import os
import numpy as np
from pycocotools.coco import COCO
from skimage import io, transform

IMGSIZE = 256

# Crop center part of image
def crop_center(img):
    m = min(img.shape[0], img.shape[1])
    x = abs(img.shape[0] - img.shape[1])/2
    if img.shape[0] >= img.shape[1]:
        return img[x : m+x, :, :]
    else:
        return img[:, x : m+x, :]

def main():
    dataDir='annotations'
    picDir='pic/test/'
    dataType='train2014'
    annFile='%s/instances_%s.json' % (dataDir,dataType)

    images_dataset_nm = './imgdata.dat'
    labels_dataset_nm = './lbldata.dat'

    # Initialize COCO
    coco=COCO(annFile)

    im_f = open(images_dataset_nm, 'wb+')
    im_f.truncate()
    lb_f = open(labels_dataset_nm, 'wb+')
    lb_f.truncate()

    for filenm in os.listdir(picDir):
        # Image preprocessing
        I = io.imread(picDir + filenm)
        # Transformed version is already normalized
        I = transform.resize(crop_center(I), (IMGSIZE, IMGSIZE))
        im_f.write(I.tobytes())

        # Label preprocessing
        imgIds = [int(filenm[-16:-4])]
        print filenm, ':', imgIds,
        myImgIds = coco.getImgIds(imgIds)
        myImg = coco.loadImgs(myImgIds)
        myImgAnnIds = coco.getAnnIds(imgIds=myImgIds, iscrowd=False)
        myImgAnns = coco.loadAnns(myImgAnnIds)
        max_area_idx = np.argmax([ann['area'] for ann in myImgAnns])
        cat = myImgAnns[max_area_idx]['category_id']
        print coco.loadCats(cat)[0]['name']
        lb_f.write(chr(cat))

    im_f.close()
    lb_f.close()


if __name__ == "__main__":
    main()