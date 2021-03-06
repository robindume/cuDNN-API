import os
import numpy as np
from pycocotools.coco import COCO
from skimage import io, transform

IMGSIZE = 227

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
    picDir='pic/train/'
    dataType='train2014'
    annFile='%s/instances_%s.json' % (dataDir,dataType)

    images_dataset_nm = './imgdata.dat'
    labels_dataset_nm = './lbldata.dat'
    ids_dataset_nm = './nmdata.dat'

    # Initialize COCO
    coco=COCO(annFile)

    im_f = open(images_dataset_nm, 'wb+')
    im_f.truncate()
    nam_f = open(ids_dataset_nm, 'wb+')
    nam_f.truncate()
    lb_f = open(labels_dataset_nm, 'wb+')
    lb_f.truncate()

    n_cats = max([cat['id'] for cat in coco.loadCats(coco.getCatIds())])

    img_names = os.listdir(picDir)
    metadata = np.array([len(img_names), IMGSIZE, IMGSIZE, 3], dtype=np.int32)
    print metadata
    im_f.write(metadata.tobytes())

    metadata_lbls = np.array([n_cats+1], dtype=np.int32)
    print metadata_lbls
    lb_f.write(metadata_lbls.tobytes())

    for filenm in img_names:
        # Label preprocessing
        imgIds = [int(filenm[-16:-4])]
        print filenm, ':', imgIds,

        nam_f.write(np.array(imgIds, dtype=np.int32).tobytes());
        
        myImgIds = coco.getImgIds(imgIds)
        myImg = coco.loadImgs(myImgIds)
        myImgAnnIds = coco.getAnnIds(imgIds=myImgIds, iscrowd=False)
        myImgAnns = coco.loadAnns(myImgAnnIds)
        if (len(myImgAnns) != 0):
        	max_area_idx = np.argmax([ann['area'] for ann in myImgAnns])
        	cat = myImgAnns[max_area_idx]['category_id']
        else:
        	cat = 0
        cat_tmp = np.zeros(shape=[n_cats+1], dtype=np.float32)
        cat_tmp[cat] = 1.0
        if (cat != 0):
        	print coco.loadCats(cat)[0]['name'], "-", cat
        lb_f.write(cat_tmp.tobytes())
        

        # Image preprocessing
        I = io.imread(picDir + filenm)
        # Transformed version is already normalized
        if (I.shape != 3):
        	I = np.dstack((I, I, I))
        I = transform.resize(crop_center(I), (IMGSIZE, IMGSIZE))
        I = I.astype('float32')
        im_f.write(I.tobytes())

    nam_f.close()
    im_f.close()
    lb_f.close()


if __name__ == "__main__":
    main()